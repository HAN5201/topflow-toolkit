#!/bin/sh

STOCK_SCRIPT=/data/local/mwan3-tuning/sdx75_set_mwan3.stock.sh
APPLY_RULES=/data/local/mwan3-tuning/apply-rules.sh

if [ ! -x "$STOCK_SCRIPT" ]; then
    logger -t topflow-mwan3 -p 3 "stock mwan3 generator is missing"
    exit 127
fi

"$STOCK_SCRIPT" "$@"
status=$?

if [ "$status" -eq 0 ] && [ -x "$APPLY_RULES" ]; then
    if ! "$APPLY_RULES" --no-reload; then
        logger -t topflow-mwan3 -p 3 "post-generation tuning failed"
    fi
fi

exit "$status"
