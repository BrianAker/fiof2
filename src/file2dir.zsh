#!/usr/bin/zsh

for x in "$@"
do
    if [[ -d "$x" ]]; then
        echo "Warning: '$x' is a directory, skipping."
        continue
    fi

    mkdir "${x%.*}" && mv "$x" "${x%.*}"
done
