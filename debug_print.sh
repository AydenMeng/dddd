#!/bin/bash
# Copyright 2026 Ayden Meng (aydenmeng@yeah.net)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FILE_DEBUG_PRINT="debug_print.sh"
INCLUDE_DEBUG_PRINT="include_$(basename $FILE_DEBUG_PRINT | tr -cd '[:alnum:]_')"

if [[ -n "${!INCLUDE_DEBUG_PRINT:-}" ]]; then
	return 0
fi

declare "$INCLUDE_DEBUG_PRINT=1"

export LANG=C

log_level="verbose"
log_stream="/dev/null"
log_verbose()
{
	echo -e " $(date): ${FUNCNAME[1]}: $*"
}

log_warn()
{
	# yellow
	echo -en "$(date): \e[1;33m Warning: \e[0m"
	echo "${FUNCNAME[1]} $*"
}

log_error()
{
	# red
	echo -en "$(date): \e[1;31m Error: \e[0m"
	echo "${FUNCNAME[1]} : $*"
}

log_cheer()
{
	# green
	echo -en "$(date): \e[1;32m Success: \e[0m"
	echo "${FUNCNAME[1]}: $*"
}

log_normal()
{
	# green
	echo "$*"
}

log_quiet()
{
	return 0
}

log_save()
{
	echo "${FUNCNAME[1]}: $*" | tee -a $log_stream
}

log()
{
	log_${log_level} "$*"
}


CALL_WHERE_DEBUG_PRINT=$(basename $0)

if [[ "$CALL_WHERE_DEBUG_PRINT" == "$FILE_DEBUG_PRINT" ]]; then
	log $@
fi
