#!/usr/bin/env bash
pkill -f "walker --gapplication-service" 2>/dev/null
sleep 0.1
exec walker --gapplication-service
