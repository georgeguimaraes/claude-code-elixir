#!/usr/bin/env elixir

# Fetches and distills GitHub comments from Phoenix/Elixir core contributors
# Usage: elixir scripts/fetch_github_wisdom.exs

Mix.install([:jason])

defmodule GitHubWisdom do
  @moduledoc """
  Fetches substantive comments from core contributors on GitHub repos.
  """

  @default_config %{
    repo: "phoenixframework/phoenix",
    user: "chrismccord",
    min_comment_length: 100,
    max_issues: 100,
    output_file: "phoenix_wisdom.md"
  }

  def run(config \\ %{}) do
    config = Map.merge(@default_config, config)

    IO.puts("🔍 Fetching issues/PRs where #{config.user} commented on #{config.repo}...")

    issues = fetch_issues_with_comments(config)
    IO.puts("   Found #{length(issues)} issues/PRs")

    IO.puts("📝 Fetching comments...")
    comments = fetch_all_comments(issues, config)
    IO.puts("   Found #{length(comments)} comments")

    IO.puts("🧹 Filtering substantive comments (>#{config.min_comment_length} chars)...")
    filtered = filter_substantive(comments, config.min_comment_length)
    IO.puts("   Kept #{length(filtered)} substantive comments")

    IO.puts("📊 Categorizing by topic...")
    categorized = categorize_comments(filtered)

    IO.puts("💾 Writing to #{config.output_file}...")
    write_markdown(categorized, config)

    IO.puts("✅ Done! Check #{config.output_file}")
  end

  defp fetch_issues_with_comments(config) do
    query = "repo:#{config.repo} commenter:#{config.user}"

    {output, 0} =
      System.cmd("gh", [
        "api", "search/issues",
        "--paginate",
        "-X", "GET",
        "-f", "q=#{query}",
        "-f", "per_page=100",
        "-f", "sort=updated",
        "--jq", ".items"
      ])

    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&Jason.decode!/1)
    |> Enum.take(config.max_issues)
  end

  defp fetch_all_comments(issues, config) do
    issues
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {issue, idx} ->
      if rem(idx, 10) == 0, do: IO.write("   #{idx}/#{length(issues)}...")
      fetch_comments_for_issue(issue, config)
    end)
    |> tap(fn _ -> IO.puts("") end)
  end

  defp fetch_comments_for_issue(issue, config) do
    number = issue["number"]

    # Fetch issue/PR comments
    issue_comments = fetch_issue_comments(config.repo, number, config.user)

    # If it's a PR, also fetch review comments (inline code comments)
    pr_comments =
      if issue["pull_request"] do
        fetch_pr_review_comments(config.repo, number, config.user)
      else
        []
      end

    (issue_comments ++ pr_comments)
    |> Enum.map(fn comment ->
      Map.merge(comment, %{
        "issue_number" => number,
        "issue_title" => issue["title"],
        "issue_url" => issue["html_url"],
        "is_pr" => issue["pull_request"] != nil
      })
    end)
  end

  defp fetch_issue_comments(repo, number, user) do
    {output, _} =
      System.cmd("gh", [
        "api", "repos/#{repo}/issues/#{number}/comments",
        "--jq", "[.[] | select(.user.login == \"#{user}\")]"
      ], stderr_to_stdout: true)

    case Jason.decode(output) do
      {:ok, comments} when is_list(comments) -> comments
      _ -> []
    end
  end

  defp fetch_pr_review_comments(repo, number, user) do
    {output, _} =
      System.cmd("gh", [
        "api", "repos/#{repo}/pulls/#{number}/comments",
        "--jq", "[.[] | select(.user.login == \"#{user}\")]"
      ], stderr_to_stdout: true)

    case Jason.decode(output) do
      {:ok, comments} when is_list(comments) ->
        Enum.map(comments, &Map.put(&1, "is_code_review", true))
      _ ->
        []
    end
  end

  defp filter_substantive(comments, min_length) do
    # Keywords that indicate explanatory/educational content
    wisdom_indicators = ~r/because|reason|issue|problem|pitfall|careful|note that|important|actually|instead|prefer|recommend|avoid|should|better|the way|internally|design|meant to|intended|works by|how we/i

    comments
    |> Enum.filter(fn c ->
      body = c["body"] || ""
      String.length(body) >= min_length
    end)
    |> Enum.map(fn c ->
      body = c["body"] || ""
      reactions = get_in(c, ["reactions", "total_count"]) || 0
      wisdom_matches = length(Regex.scan(wisdom_indicators, body))

      # Score: reactions * 10 + wisdom_keywords * 5 + length/100
      score = reactions * 10 + wisdom_matches * 5 + String.length(body) / 100
      Map.put(c, "wisdom_score", score)
    end)
    |> Enum.sort_by(fn c -> -c["wisdom_score"] end)
  end

  defp categorize_comments(comments) do
    categories = %{
      "LiveView" => ~r/live_?view|live_?component|phx-|socket|assign|mount|handle_/i,
      "Channels & PubSub" => ~r/channel|pubsub|socket|broadcast|presence/i,
      "Routing" => ~r/route|plug|pipeline|scope|~p|verified_routes/i,
      "Controllers & Views" => ~r/controller|view|render|template|layout|component/i,
      "Ecto Integration" => ~r/ecto|repo|changeset|schema|query/i,
      "Testing" => ~r/test|assert|mock|fixture|conn_?test/i,
      "Performance" => ~r/perform|optimi|fast|slow|memory|cache/i,
      "Security" => ~r/secur|auth|csrf|token|protect|sanitize/i,
      "Configuration" => ~r/config|endpoint|application|env/i,
      "Error Handling" => ~r/error|exception|rescue|catch|fault/i,
      "Best Practices" => ~r/pattern|practice|recommend|should|prefer|avoid|instead/i
    }

    categorized =
      Enum.reduce(comments, %{"Uncategorized" => []}, fn comment, acc ->
        body = comment["body"] || ""
        title = comment["issue_title"] || ""
        text = body <> " " <> title

        category =
          Enum.find_value(categories, "Uncategorized", fn {cat, regex} ->
            if Regex.match?(regex, text), do: cat
          end)

        Map.update(acc, category, [comment], &[comment | &1])
      end)

    # Remove empty categories and reverse lists
    categorized
    |> Enum.filter(fn {_, comments} -> comments != [] end)
    |> Enum.map(fn {cat, comments} -> {cat, Enum.reverse(comments)} end)
    |> Enum.into(%{})
  end

  defp write_markdown(categorized, config) do
    content = """
    # Phoenix Wisdom from #{config.user}

    > Auto-extracted substantive comments from [#{config.repo}](https://github.com/#{config.repo})
    > Generated: #{Date.utc_today()}

    ---

    #{format_categories(categorized)}
    """

    File.write!(config.output_file, content)
  end

  defp format_categories(categorized) do
    # Sort categories by number of comments
    categorized
    |> Enum.sort_by(fn {_, comments} -> -length(comments) end)
    |> Enum.map(fn {category, comments} ->
      """
      ## #{category} (#{length(comments)} comments)

      #{format_comments(comments)}
      """
    end)
    |> Enum.join("\n---\n\n")
  end

  defp format_comments(comments) do
    comments
    |> Enum.take(20)  # Limit per category
    |> Enum.map(&format_comment/1)
    |> Enum.join("\n\n")
  end

  defp format_comment(comment) do
    body = comment["body"] |> String.trim()
    url = comment["issue_url"]
    title = comment["issue_title"]
    date = comment["created_at"] |> String.slice(0, 10)
    is_code_review = comment["is_code_review"]
    reactions = get_in(comment, ["reactions", "total_count"]) || 0

    type_badge = if is_code_review, do: "🔍 Code Review", else: "💬 Comment"
    reaction_badge = if reactions > 0, do: " | 👍 #{reactions}", else: ""
    wisdom_score = comment["wisdom_score"] || 0
    score_badge = if wisdom_score > 5, do: " | 📚 #{Float.round(wisdom_score, 1)}", else: ""

    """
    ### [#{title}](#{url})
    #{type_badge} | #{date}#{reaction_badge}#{score_badge}

    #{body}
    """
  end
end

# Parse CLI args
{opts, _, _} = OptionParser.parse(System.argv(), switches: [
  repo: :string,
  user: :string,
  max: :integer,
  min_length: :integer,
  output: :string
])

config =
  Enum.reduce(opts, %{}, fn
    {:repo, v}, acc -> Map.put(acc, :repo, v)
    {:user, v}, acc -> Map.put(acc, :user, v)
    {:max, v}, acc -> Map.put(acc, :max_issues, v)
    {:min_length, v}, acc -> Map.put(acc, :min_comment_length, v)
    {:output, v}, acc -> Map.put(acc, :output_file, v)
  end)

GitHubWisdom.run(config)
