#!/usr/bin/bash
#
# Copyright 2013 RackTop Systems
# http://www.racktopsystems.com/
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# Description:
# Purpose of the script is to rapidly deploy vdbench and Oracle JRE in
# order to simplify testing of the storage before system is deemed prod-
# ready. This script was written specifically for BrickStor systems, and
# there is absolutely no assurance that it will work elsewhere. In fact,
# due to the non-standard paths being used, it will most likely bomb out
# gloriously elsewhere.

TAR_CMD=/usr/bin/tar
WGET_CMD=/usr/bin/wget
JAVA_HOME=.
JAVA_BIN=${JAVA_HOME}/bin
DEPFORCE=${DEPFORCE:=0}

rt_root_dir=/racktop
work_dir=/tmp
arg=$1
siteurl=repo.racktopsystems.com
debug=1

function command_exists () {

	local cmd=$1
	if [[ -x ${cmd} ]]; then
		return 0
	else
		return 1
	fi
}

function print_info () {
	printf "[INFO] %s\n" "$@"
}

function print_warn () {
	printf "[WARN] %s\n" "$@"
}

function deploy_vdbench () {
	local vdbech_archive=$1
	printf "[INFO] %s\n" "Deploying vdbench to /racktop/vdbench."

	command_exists ${rt_root_dir}/vdbench/vdbench.bash; retcode=$?

	## If we have $DEPFORCE variable set, we will force re-deployment.
	## This should not be a serious change and should in fact be idempotent.
	if [[ ${retcode} -eq "0" ]]; then
		if [[ ${DEPFORCE} -eq "1" ]]; then
			print_warn "vdbench may already be deployed, redeploying due to DEPFORCE=1"
			${TAR_CMD} Pxzf ${vdbech_archive}; retcode=$?

			if [[ ${retcode} -ne "0" ]]; then
				print_warn "There was an error during unpacking of vdbench archive. Please check manually."
			fi
		
		else
			print_info "vdbench may already be deployed, will not re-deploy. To force re-deploy export DEPFORCE=1 or set in script."
			return 0
		fi

	else
		${TAR_CMD} Pxzf ${vdbech_archive}; retcode=$?

		if [[ ${retcode} -ne "0" ]]; then
			print_warn "There was an error during unpacking of vdbench archive. Please check manually."
		fi
	fi

	return 0
}

function deploy_jre () {
	local jre_archive=$1
	print_info "Deploying Oracle JRE to /racktop/jre1.7.0_13."
	## Because this archive is built using relative paths, we will first switch
	## to racktop's base path, and then perform extraction.
	cd ${rt_root_dir}

	command_exists ${rt_root_dir}/jre1.7.0_13/bin/java; retcode=$?

	## If we have $DEPFORCE variable set, we will force re-deployment.
	## This should not be a serious change and should in fact be idempotent.
	if [[ ${retcode} -eq "0" ]]; then
		if [[ ${DEPFORCE} -eq "1" ]]; then
			print_warn "JRE may already be deployed, redeploying due to DEPFORCE=1"
			${TAR_CMD} xzf ${jre_archive}; retcode=$?
			
			if [[ ${retcode} -ne "0" ]]; then
				print_warn "There was an error during unpacking of JRE archive. Please check manually."
			fi

		else
			print_info "JRE may already be deployed, will not re-deploy. To force re-deploy export DEPFORCE=1 or set in script."
			return 0
		fi

	else
		${TAR_CMD} xzf ${jre_archive}; retcode=$?
		if [[ ${retcode} -ne "0" ]]; then
			print_warn "There was an error during unpacking of JRE archive. Please check manually."
		fi
	fi


	if [[ ${retcode} -ne "0" ]]; then
		print_warn "There was an error during unpacking of vdbench archive. Please check manually."
	fi

	return 0
}

function exit_error () {
	## Function expects one argument: short error message.
	printf "[CRIT] %s\n" "Exiting early due to error: $@"
	## Maybe add some clean-up code here later.
	exit 1
}

function get_file () {
	local work_dir=/tmp ## This is where all action takes place
	local src_file=$1 ## Full pathname, including http://
	local file=$(basename ${src_file}) ## Basename of the file, with path stripped off

	${WGET_CMD} --no-check-certificate -O ${work_dir}/${file} ${src_file}

	if [[ $? -ne "0" ]]; then ## Something went wrong, we did not succeed.
		printf "[CRIT] %s\n" "Download of ${src}/${file} failed."
		return 1
	else
		return 0
	fi
}

case $arg in

	bootstrap)
		## We can only run this if we are root, otherwise we terminate early.
		if [[ ${UID} -ne "0" ]]; then
			exit_error "User must be root equivalent. Cannot continue."
		fi

		# [[ ${debug} -ge "1" ]] && set -x
		## This is used to actually set things up and prepare system
		## for stress testing. We need to download and deploy vdbench
		## as well as Oracle JRE.
		vdbtgz=racktop-vdbench503.tgz
		jretgz=jre-7u13-solaris-i586.tgz
		files[1]=${vdbtgz}; files[2]=${jretgz}

		for file in ${files[@]}; do
			src=http://${siteurl}/sf/archives/${file} ## actual file we need
			src_md5=http://${siteurl}/sf/archives/${file}.md5sum ## md5sum of the file that we need

			## If the file already exists, let's make sure we do not download it
			## again, for no good reason. We will instead download .md5sum file
			## to confirm that we have correct file, else we will download again.

			if [[ -f  ${work_dir}/${file} ]]; then
				printf "[INFO] %s\n" "File ${file} already downloaded, doing checksum validation."
				get_file ${src_md5}; retcode=$? ## Download .md5sum and return 0 if successful
				if [[ ${retcode} -eq "0" ]]; then
					f=${work_dir}/${file}
					f_md5=${work_dir}/${file}.md5sum

					## We check to see if the md5sum of the file we are working on
					## actually matches the checksum file contents, and if it does
					## we will use this file, otherwise we retrieve it again.
					if [[ $(md5sum ${f}|cut -f1 -d' ') == $(cat ${f_md5}) ]]; then
						printf "[INFO] %s\n" "Existing file ${file} passed checksum validation, will use this file."
					else
						printf "[WARN] %s\n" "Existing file ${file} did not pass checksum validation, will download again."
						## We are just moving this file out of the way, instead of deleting it.
						mv ${work_dir}/${file} ${work_dir}/${file}.old
						get_file ${src}; retcode=$?

						## If we are failing when we attempt to retrieve file, we cannot continue
						## and will exit with status 1.
						if [[ ${retcode} -ne "0" ]]; then
							exit_error "Download of ${file} did not succeed."
						fi
					fi
				fi
			## File does not exist in the directory, so we need to get it.
			else
				printf "[INFO] %s\n" "Attempting to dowload file ${file}."
				get_file ${src}; retcode=$?
				## If we are failing when we attempt to retrieve file, we cannot continue
				## and will exit with status 1.
				if [[ ${retcode} -ne "0" ]]; then
					exit_error "Download of ${file} did not succeed."
				fi
			fi
		done

		## Unpack the files, making sure that we actually have a structure
		## in place before we unpack. We will abort here if the $rt_root_dir does
		## not exist on the system.
		if [[ ! -d ${rt_root_dir} ]]; then
			print_warn "Directory ${rt_root_dir} does not exist, will not continue. Create manually if this is expected."
			exit_error "Fix missing directory issue."
		fi

		## This will stage vdbench in /racktop/vdbench, without making any other changes
		deploy_vdbench ${work_dir}/${files[1]}
		deploy_jre ${work_dir}/${files[2]}

		## Unpack vdbench first, which does not use relative paths, handle
		## oracle separately.
		## tar xzf ${work_dir}/${vdbtgz}

		# [[ ${debug} -ge "1" ]] && set +x
		;;

	*) 
		exit_error "Expected argument. Wrong argument, or no argument given."
	;;
esac