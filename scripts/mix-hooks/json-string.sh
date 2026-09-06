#!/bin/bash

# JSON.sh leaves strings escaped. Decode only the fields consumed by the hook.
json_decode_string() {
  local LC_ALL=C
  local text=$1 char hex code low oct byte i
  local bytes=()
  [[ $text == \"*\" ]] || return 1
  text=${text:1:${#text}-2}
  decoded=
  while [[ -n $text ]]; do
    char=${text%%\\*}
    decoded+=$char
    text=${text:${#char}}
    [[ -n $text ]] || break
    text=${text:1}
    char=${text:0:1}
    text=${text:1}
    case $char in
      \"|\\|/) decoded+=$char ;;
      b) decoded+=$'\b' ;;
      f) decoded+=$'\f' ;;
      n) decoded+=$'\n' ;;
      r) decoded+=$'\r' ;;
      t) decoded+=$'\t' ;;
      u)
        hex=${text:0:4}
        [[ $hex =~ ^[0-9a-fA-F]{4}$ ]] || return 1
        code=$((16#$hex))
        text=${text:4}
        if (( code >= 55296 && code <= 56319 )); then
          [[ ${text:0:2} == '\u' ]] || return 1
          hex=${text:2:4}
          [[ $hex =~ ^[0-9a-fA-F]{4}$ ]] || return 1
          low=$((16#$hex))
          (( low >= 56320 && low <= 57343 )) || return 1
          code=$((65536 + (code - 55296) * 1024 + low - 56320))
          text=${text:6}
        elif (( code >= 56320 && code <= 57343 )); then
          return 1
        fi
        # Paths and Bash variables cannot contain NUL.
        (( code != 0 )) || return 1
        if (( code < 128 )); then
          bytes=("$code")
        elif (( code < 2048 )); then
          bytes=("$((192 | code >> 6))" "$((128 | code & 63))")
        elif (( code < 65536 )); then
          bytes=("$((224 | code >> 12))" "$((128 | code >> 6 & 63))" "$((128 | code & 63))")
        else
          bytes=("$((240 | code >> 18))" "$((128 | code >> 12 & 63))" "$((128 | code >> 6 & 63))" "$((128 | code & 63))")
        fi
        for i in "${bytes[@]}"; do
          printf -v oct '%03o' "$i"
          printf -v byte '%b' "\\0$oct"
          decoded+=$byte
        done
        ;;
      *) return 1 ;;
    esac
  done
}

json_quote() {
  local LC_ALL=C
  local value=$1 i oct char escape
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  for ((i=1; i<32; i++)); do
    printf -v oct '%03o' "$i"
    printf -v char '%b' "\\0$oct"
    printf -v escape '\\u%04x' "$i"
    value=${value//"$char"/"$escape"}
  done
  printf '"%s"' "$value"
}
