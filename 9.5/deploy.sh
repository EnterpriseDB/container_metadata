#!/bin/bash

START_REGISTRY=0
UNATTNDED_MODE=0
RAR_LOG_FILE=/tmp/$tmpdir/rar_$$.log
REMOVE_COMPONENT_PROVIDED=0
DATABASE_NAME_PROVIDED=0
CLEANUP_PROVIDED=0
UPDATE_COMPONENT_PROVIDED=0
PROJECT_NAME_PROVIDED=0
DEPLOY_CONTAINER=0
PUSH_IMAGE_IN_LOCAL_REPO=0
CREATE_TEMPLATE=0
REGISTRY_PREFIX_PROVIDED=0
LOCAL_REGISTRY_PROVIDED=0
REGISTRY_NAMESPACE_PROVIDED=0
IMAGE_TAG_PROVIDED=0
FORCE_TAGGING=""

## Fetch the absolute directory of the script
RAR_OLD_PWD=$PWD
DIRNAME=$(cd `dirname $0` && pwd)
cd $DIRNAME
RAR_WD=$PWD
cd ${RAR_OLD_PWD}

PS_CMD="ps"

RAR_SHELL_BASH=0
RAR_SHELL=`$PS_CMD e | grep $$ | grep -v grep | awk '{print $5}'`
if [ x"${RAR_SHELL}" = x"/bin/bash" -o x"${RAR_SHELL}" = x"bash" -o x"${RAR_SHELL}" = x"-bash" ];
then
  RAR_SHELL_BASH=1
fi

## Check presence of tput utility on the system
RAR_TPUT_PRESENT=0
which tput > /dev/null 2>&1
if [ $? -eq 0 -a ${RAR_SHELL_BASH} -eq 1 ]
then
  RAR_TPUT_PRESENT=1
fi

## Check presence of stty utility on the system
RAR_STTY_PRESENT=0
which stty > /dev/null 2>&1
if [ $? -eq 0 -a ${RAR_SHELL_BASH} -eq 1 ]
then
  RAR_STTY_PRESENT=1
fi
RAR_STTY_OUTPUT=

# ---------------------------

# Message related variables
# ---------------------------
export MSG_DEBUG=0
export MSG_EMPTY=1
export MSG_INFO=2
export MSG_WARN=3
export MSG_TEST=4
export MSG_TEST_VALUE=5
export MSG_CRITICAL=6

# Not part of the above enum
export MSGIsTesting=0

# ---------------------------

# $1 - Heading text
MessageHeading()
{
    echo ""
    echo "-----------------------------------------------------"
    echo "$1"
    echo "-----------------------------------------------------"
}

# $1 - Message type
# $2 - Message text; in case of MSG_EMPTY, this value is ignored
# $3 - Suppress message; do not print any messages

Message()
{
    prefix="--> "
    MessageType="$1"
    MessageText="$2"
    blnSuppressMessage="$3"

    if [[ ! -z "$blnSuppressMessage" ]];
    then
        return
    fi


    # If no value given for a test condition message, ensure the next message appears on the next line
    if [[ "$MSGIsTesting" -eq 1 && "$MessageType" != "$MSG_TEST_VALUE" ]];
    then
        MSGIsTesting=0
        echo "[SKIPPING: NO VALUE PROVIDED]";
    fi


    case $MessageType in
        "$MSG_DEBUG")
            if [[ -n "$VERBOSE" ]];
            then
                prefix="$prefix [Debug]"
                echo "$prefix $MessageText"
            fi
            ;;
        "$MSG_EMPTY")
            echo;
            ;;
        "$MSG_INFO")
            prefix="$prefix [Info]"
            echo "$prefix $MessageText"
            ;;
        "$MSG_WARN")
            prefix="$prefix [Warning]"
            echo "$prefix $MessageText"
            ;;
        "$MSG_TEST")
            MSG_IsTesting=1
            prefix="$prefix [Test]"
            echo -n "$prefix $MessageText... "
            ;;
        "$MSG_TEST_VALUE")
            echo "$2"
            ;;
        "$MSG_CRITICAL")
            prefixE="$prefix [Error]"

            MessageHeading "CRITICAL ERROR"

            echo "$prefixE Script exiting because of the following error:"
            echo "$prefixE $MessageText"
            echo
            echo -n "$prefix Current working directory and stack is:"
            dirs -l -v
            echo
            exit
            ;;
        ?)
            Usage
            exit
            ;;
    esac
}

#--------------------------------
# Load image into registry

LoadImageIntoRegistry(){

	# Get Image file name
	IMAGE_FILE_NAME=`GetRequiredFileNames tar`
	# Load image
	if [ -n "$IMAGE_FILE_NAME" ];
	then 
		Message $MSG_INFO "Loading container image $IMAGE_FILE_NAME"
		docker load < $IMAGE_FILE_NAME
	fi
}

#--------------------------------
# Get filename without extension

RemoveExtensionFromFileName(){

	FULL_NAME=$1
	FILE_NAME=`echo $FULL_NAME | sed 's/\.[^.]*$//'`
	echo $FILE_NAME
	
}

#-------------------------------
# Tag image in registry

TagImageToLatest(){

	# Remove extension name from image file name
	REGISTRY_IMAGE=`RemoveExtensionFromFileName $IMAGE_FILE_NAME`
	# Get latest tag name
	LATEST_TAG=`echo $REGISTRY_IMAGE | cut -f1 -d':'`
	# Tag the image in repository
	if [ -n "$REGISTRY_IMAGE" ];
	then
		Message $MSG_INFO "Tagging $REGISTRY_IMAGE to ${LATEST_TAG}:latest"
		docker tag ${FORCE_TAGGING} $REGISTRY_IMAGE ${LATEST_TAG}:latest
	fi
}

#-------------------------------
# Function to create template

CreateTemplate(){

	SELECTED_COMPONENT=$1

	if [ "$SELECTED_COMPONENT" = "edb-as" ];
        then
                SELECTED_COMPONENT=ppas
        fi
	
	# Get yaml file name
	YAML_FILE_NAME=`GetRequiredFileNames yaml`

	# Create template
	if [ -n "$YAML_FILE_NAME" ];
	then
		Message $MSG_INFO "Creating template $YAML_FILE_NAME"

		if [ $REMOVE_COMPONENT_PROVIDED != 1 ]
        	then
                	CreateProject "${PROJECT_NAME}"
    		fi

    		LoginOpenShift "${OPENSHIFT_USER}" "${PROJECT_NAME}"
    		SwitchProject "${PROJECT_NAME}"

		oc create -f $YAML_FILE_NAME
	fi
}

#-------------------------------

CreateOpenShiftProject(){
	
	oc new-project $1
}

#------------------------------

SwitchProject(){

	oc project $1 || Die "Unable to switch to project '${1}'. Check project name."
}

#------------------------------

CreateOpenShiftApp(){

	oc new-app $1
}

#-----------------------------

LoginOpenShift(){
	
	oc login -u $1 -n $2
}

#----------------------------
# Function to get file name

GetRequiredFileNames(){

	EXT=$1
	FILE_NAME=`find * | grep *${SELECTED_COMPONENT}*.${EXT}`
	echo $FILE_NAME	
}

#------------------------------
# Deploy selected container

DeployContainer(){

	SELECTED_COMPONENT=$1

	if [ $REGISTRY_PREFIX_PROVIDED = 0 ]
	then
		Message $MSG_CRITICAL "Please provide registry prefix using -rp|--registry-prefix to pull image from registry."
	fi

	if [ $IMAGE_TAG_PROVIDED = 0 ]
	then
		IMAGE_TAG=latest
	fi

	PullImageFromRegistry $SELECTED_COMPONENT
}

#-------------------------------
# Clean OpenShift PPAS project

CleanPPAS(){

	if [ $DATABASE_NAME_PROVIDED != 1 ]
    	then
		Message $MSG_CRITICAL "Databse name not provided to clean project. Please provide database name using -dn|--dbname switch."
                exit 1
	fi
	
	ReadValue "Enter NFS Mount Directory Path Used By Persistent Volume:" NFS_PATH "/volumes/edb-$EDB_SHORT_VERSION"

	if [ "$SELECTED_COMPONENT" = "edb-as" ];
        then
		SELECTED_COMPONENT=ppas
	fi
	
	YAML_FILE_NAME=`GetRequiredFileNames yaml`
	F_NAME=`RemoveExtensionFromFileName ${YAML_FILE_NAME}`

	SwitchProject ${PROJECT_NAME} 
        oc delete template ${F_NAME}
        oc delete dc $DATABASE_NAME
        oc delete service $DATABASE_NAME-service

	rm -f ${NFS_PATH}/$EDB_MAJOR_VERSION/.$DATABASE_NAME-master || Die "Remove ${NFS_PATH}/$EDB_MAJOR_VERSION/.$DATABASE_NAME-master as root user."
}

#-------------------------------
# Clean OpenShift BART project

CleanBART(){

	if [ $DATABASE_NAME_PROVIDED != 1 ]
        then
                Message $MSG_CRITICAL "Databse name not provided to clean project. Please provide database name using -dn|--dbname switch."
                exit 1
        fi

	YAML_FILE_NAME=`GetRequiredFileNames yaml`
	F_NAME=`RemoveExtensionFromFileName ${YAML_FILE_NAME}`

	SwitchProject ${PROJECT_NAME}
        oc delete template ${F_NAME}
        oc delete dc ${DATABASE_NAME}-bart

}

#-------------------------------
# Clean OpenShift PEM project

CleanPEM(){

	YAML_FILE_NAME=`GetRequiredFileNames yaml`
	SwitchProject ${PROJECT_NAME} 
        oc delete template ${YAML_FILE_NAME}
        oc delete dc ${YAML_FILE_NAME}
        oc delete service pem-service
}

#-------------------------------
# Remove selected container

RemoveContainer(){

	SELECTED_COMPONENT=$1

	if [ $PROJECT_NAME_PROVIDED -eq 0 ];
        then
                Message $MSG_CRITICAL "Project name is not provided. Please provide project name using -p|--project switch"
        fi

	case "$SELECTED_COMPONENT" in
                edb-as)
                        CleanPPAS
                        ;;
                edb-bart)
			CleanBART
                        ;;

                pem)
			CleanPEM
                        ;;
                *)
                        Message $MSG_CRITICAL "Selected component $SELECTED_COMPONENT is not valid. Please enter valid value."
                        exit 1
        esac	
}

#--------------------------------
# Clean selected project

CreateProject(){

	PROJECT_NAME=$1

        CreateOpenShiftProject "${PROJECT_NAME}"
	
}

# -----------------------------
# Fatal error handler

Die()
{
  echo ""
  if [ ${RAR_TPUT_PRESENT} -eq 1 -a $# -gt 0 ]
  then
    Message $MSG_CRITICAL "$*"
  else
    Message $MSG_CRITICAL "$*"
  fi
  echo ""
  cd ${RAR_WD}
  Message $MSG_CRITICAL "$*" >> ${RAR_LOG_FILE}
  exit 1
}

#---------------------------------------

Question()
{
  if [ ${RAR_TPUT_PRESENT} -eq 1 -a $# -eq 2 ]
  then
    echo -e "\E[34;49m"$1 "\E[32;49m"[ $2 ] "\E[34;49m": && tput sgr0
  elif [ ${RAR_TPUT_PRESENT} -eq 1 -a $# -gt 0 ]
  then
    echo -e "\E[34;49m"$* && tput sgr0
  else
    echo $*
  fi
  echo QUE: $* >> ${RAR_LOG_FILE}
}

#------------------------------------------

ReadValue()
{

  QUESTION=${1}
  VARIABLE=${2}
  DEFAULT_VALUE=${3}
  VALIDATOR=${4}
  DESC_VARIABLE=${5}
  RETURN_VALUE=0

  if [ ${UNATTNDED_MODE} -eq 1 ]
  then
    eval ${VARIABLE}=${DEFAULT_VALUE}
    if [ x"${VALIDATOR}" != x"" -a x"${VALIDATOR}" != x" " ]
    then
       ${VALIDATOR} "${!VARIABLE}" 1
       if [  $? -ne 1 ]
       then
          Die "\"${!VARIABLE}\" is not valid value for the variable \"${DESC_VARIABLE}\""
       fi
    fi
    return 1
  fi

  while [ ${RETURN_VALUE} -ne 1 ]; do
    Question "${1}" "${DEFAULT_VALUE}"
    RETURN_VALUE=1
    read ${VARIABLE}
    # if no input provided, set the variable value to the default value (if any)
    if [ x"${!VARIABLE}" = x"" -a x"${DEFAULT_VALUE}" != x"" ]
    then
      eval ${VARIABLE}=${DEFAULT_VALUE} 2>/dev/null
    fi
    if [ x"${VALIDATOR}" != x"" -a x"${VALIDATOR}" != x" " ]
    then
       ${VALIDATOR} "${!VARIABLE}" 1
       RETURN_VALUE=$?
    fi
  done
  return ${RETURN_VALUE}
}

#---------------------

GetImageID(){

       SELECTED_COMPONENT=$1
       IMAGE_TAG=$2

       IMAGE_ID=`docker images | grep ${REGISTRY_PREFIX}/${REGISTRY_NAMESPACE}/${SELECTED_COMPONENT} | grep ${IMAGE_TAG} | awk '{print $3}'`
       
       if [ -z "$IMAGE_ID" ];
       then
               Message $MSG_CRITICAL "No image found in local repository."             
       fi

       echo $IMAGE_ID
}

#---------------------

PullImageFromRegistry(){

	SELECTED_COMPONENT=$1

	docker pull ${REGISTRY_PREFIX}/${REGISTRY_NAMESPACE}/${SELECTED_COMPONENT}:${IMAGE_TAG}
	IMAGE_ID=`GetImageID $SELECTED_COMPONENT ${IMAGE_TAG}`

	Message $MSG_INFO "Tagging image to ${SELECTED_COMPONENT}:${IMAGE_TAG}"
	docker tag ${FORCE_TAGGING} $IMAGE_ID ${SELECTED_COMPONENT}:${IMAGE_TAG}

	if [ "$SELECTED_COMPONENT" = "edb-as" ];
	then
		if [[ ${IMAGE_TAG} == ${EDB_MAJOR_VERSION}* ]];
		then
			Message $MSG_INFO "Tagging image to ppas${EDB_SHORT_VERSION}:latest"
			docker tag ${FORCE_TAGGING} $IMAGE_ID ppas${EDB_SHORT_VERSION}:latest
		fi
	fi
}

#---------------------

PushImageToLocalRepository(){

	COMPONENT=$1

	if [ -z "${REGISTRY_PREFIX}" ];
        then
                Message $MSG_CRITICAL "Please provide the address of registry from where the image is pulled using -rp|--registry-prefix switch."
        fi

	docker tag ${FORCE_TAGGING} ${REGISTRY_PREFIX}/${REGISTRY_NAMESPACE}/${COMPONENT}:${IMAGE_TAG} ${LOCAL_REGISTRY}/${REGISTRY_NAMESPACE}/${COMPONENT}:${IMAGE_TAG}
        docker push ${LOCAL_REGISTRY}/${REGISTRY_NAMESPACE}/${COMPONENT}:${IMAGE_TAG}

        if [ "$COMPONENT" = "edb-as" ];
        then
		if [[ ${IMAGE_TAG} == ${EDB_MAJOR_VERSION}* ]];
		then
			docker tag ${FORCE_TAGGING} ${REGISTRY_PREFIX}/${REGISTRY_NAMESPACE}/${COMPONENT}:${IMAGE_TAG} ${LOCAL_REGISTRY}/${REGISTRY_NAMESPACE}/ppas${EDB_SHORT_VERSION}:${IMAGE_TAG}
               		docker push ${LOCAL_REGISTRY}/${REGISTRY_NAMESPACE}/ppas${EDB_SHORT_VERSION}:${IMAGE_TAG}
		fi
        fi

}

#---------------------

StartRegistry(){

	docker run -d -p 5000:5000 --restart=always --name registry registry:2
}

#-------------------------------

ResetComponentSelection()
{
  RAR_INSTALL_PPAS=N
  RAR_INSTALL_BART=N
  RAR_INSTALL_PEM=N
}

#--------------------------------------
# Select components based on user input

ComponentSelection()
{
  local LRAR_COMPONENTS=${1}
  local LRAR_NO_COMPONENTS=`echo ${LRAR_COMPONENTS} | awk -F, '{print NF}'`
  local LRAR_INDEX=1

  ResetComponentSelection

  while ((LRAR_INDEX <= ${LRAR_NO_COMPONENTS}))
  do
    local LRAR_COMPONENT=`echo ${LRAR_COMPONENTS} | cut -d, -f${LRAR_INDEX}`
    (( LRAR_INDEX = LRAR_INDEX + 1));
    case ${LRAR_COMPONENT} in
    edb-as)
        RAR_INSTALL_PPAS=Y
      ;;
    edb-bart)
        RAR_INSTALL_BART=Y
      ;;
    pem)
        RAR_INSTALL_PEM=Y
      ;;
    *)
      Die "'${LRAR_COMPONENT}' is not a valid component."
      ;;
    esac
  done
}

# ---------------------------

Info()
{
  LRAR_SHOW_IN_ANYCASE=$1
  if [ x"${LRAR_SHOW_IN_ANYCASE}" = x"1" ]
  then
    shift
  elif [ ${RAR_UNATTNDED_MODE} -eq 1 ]
  then
    return
  fi
  if [ ${RAR_TPUT_PRESENT} -eq 1 -a $# -gt 0 ]
  then
    echo -e "\E[32;49m""$*" && tput sgr0
  else
    echo $*
  fi
  echo INFO: $* >> ${RAR_LOG_FILE}
}

#-----------------------------

Usage()
{
   Additional_COMPS=""
   LRAR_SCRIPTNAME=`basename $0`

   MessageHeading "USAGE: ${PWD}/${LRAR_SCRIPTNAME} <options>"
   Info  1 "options:"
   Info  1 "   -c   | --components            <component list>             - Comma Separated Component List"
   Info  1 "                                                                 (Default: edb-as,edb-bart)"
   Info  1 "   -u   | --update                <component name>             - Update component"
   Info  1 "                                                                 (Values: edb-as,edb-bart)"
   Info  1 "   -r   | --remove                <Remove component list>      - Comma Separated Component List"
   Info  1 "                                                                 (Values: edb-as,edb-bart)"
   Info  1 "   -dn  | --dbname                <Database name>              - Database name required for cleanup"
   Info  1 "                                                                 (Default: edb)"
   Info  1 "   -sr  | --startregistry         <Start Registry>             - Start Registry"
   Info  1 "   -p   | --project               <Project Name>               - Project Name."
   Info  1 "   -dc  | --deploy-container      <Deploy Container>           - Deploys container in registry."
   Info  1 "   -rp  | --registry-prefix       <Registry Prefix>            - Registry prefix to pull image."
   Info  1 "   -rn  | --registry-namespace    <Registry Namespace>         - Registry namespace to pull image."
   Info  1 "                                                                 (Default: edb)"
   Info  1 "   -lr  | --local-registry        <Local Registry>             - Local registry address."
   Info  1 "                                                                 (Default: localhost:5000)"
   Info  1 "   -pi  | --push-image            <Push Image>                 - Push image in local repository."
   Info  1 "   -it  | --image-tag             <Image Tag>                  - Tag of image in registry."
   Info  1 "                                                                 (Default: latest)"
   Info  1 "   -ct  | --create-template       <Create Template>            - Creates template."
   Info  1 "   -ft  | --force-tagging         <Force Tagging>              - Force tagging."
   Info  1 "   -h   | --help                  <help>                       - Shows this help."

   if [ x"$1" != x"" ]
   then
     exit $1
   fi
}

#--------------------------------
# Process command line switches

ProcessCommandLine()
{
  RAR_NO_PROCD_CMD=1
  case $1 in
  -c|--components)
     if [ ${#} -lt 2 ]
     then
       Usage 2
     fi
     ComponentSelection ${2}
     RAR_NO_PROCD_CMD=2
     ;;
  -u|--update)
    if [ ${#} -lt 2 ]
     then
       Usage 2
     fi
     UPDATE_CONTAINER=$2
     UPDATE_COMPONENT_PROVIDED=1
     RAR_NO_PROCD_CMD=2
     ;;
  -r|--remove)
    if [ ${#} -lt 2 ]
     then
       Usage 2
     fi
     REMOVE_COMPONENT_NAME=${2}
     REMOVE_COMPONENT_PROVIDED=1
     RAR_NO_PROCD_CMD=2
     ;;
  -dn|--dbname )
    if [ ${#} -lt 2 ]
     then
       Usage 2
     fi
     DATABASE_NAME=${2}
     DATABASE_NAME_PROVIDED=1
     RAR_NO_PROCD_CMD=2
     ;;
  -p|--project)
    if [ ${#} -lt 2 ]
     then
       Usage 2
     fi
     PROJECT_NAME=${2}
     PROJECT_NAME_PROVIDED=1
     RAR_NO_PROCD_CMD=2
     ;;
  -dc|--deploy-container)
     DEPLOY_CONTAINER=1
     RAR_NO_PROCD_CMD=1
     ;;
  -pi|--push-image)
     PUSH_IMAGE_IN_LOCAL_REPO=1
     RAR_NO_PROCD_CMD=1
     ;;
  -rp|--registry-prefix)
     if [ ${#} -lt 2 ]
     then
       Usage 2
     fi
     REGISTRY_PREFIX=${2}
     REGISTRY_PREFIX_PROVIDED=1
     RAR_NO_PROCD_CMD=2
     ;;
  -lr|--local-registry)
     if [ ${#} -lt 2 ]
     then
       Usage 2
     fi
     LOCAL_REGISTRY=${2}
     LOCAL_REGISTRY_PROVIDED=1
     RAR_NO_PROCD_CMD=2
     ;;
  -rn|--registry-namespace)
     if [ ${#} -lt 2 ]
     then
       Usage 2
     fi
     REGISTRY_NAMESPACE=${2}
     REGISTRY_NAMESPACE_PROVIDED=1
     RAR_NO_PROCD_CMD=2
     ;;
  -it|--image-tag)
     if [ ${#} -lt 2 ]
     then
       Usage 2
     fi
     IMAGE_TAG=${2}
     IMAGE_TAG_PROVIDED=1
     RAR_NO_PROCD_CMD=2
     ;;
  -ct|--create-template)
     CREATE_TEMPLATE=1
     RAR_NO_PROCD_CMD=1
     ;;
  -ft|--force-tagging)
     FORCE_TAGGING="-f"
     RAR_NO_PROCD_CMD=1
     ;;
  -h|--help)
     Usage 0
     ;;
  -sr|--startregistry)
     START_REGISTRY=1
     RAR_NO_PROCD_CMD=1
     ;;
  *)
     RAR_NO_PROCD_CMD=0
     Message $MSG_CRITICAL "Unknown command-line argument:'$1' (Ignored)"
     Usage 1
     ;;
  esac
}
 
###############
# User Inputs #
###############

MessageHeading "PostgresPlus Containers"

##################################
# Process command line arguments #
##################################

# Throw error if no argument is passed.
if [ $# -eq 0 ]; then
    Message $MSG_CRITICAL "No argument is provided. Please check help with --help switch."
fi

while [ $# -ne 0 ];
do
   RAR_NO_PROCD_CMD=0
   ProcessCommandLine $*
   INDEX=0
   while [ "$INDEX" != "${RAR_NO_PROCD_CMD}" ]; do
     shift
     INDEX=`expr $INDEX + 1`
   done
done

EDB_MAJOR_VERSION=9.5

EDB_SHORT_VERSION=`echo $EDB_MAJOR_VERSION | sed 's/\.//'`

if [ $PROJECT_NAME_PROVIDED -eq 0 ];
then
        PROJECT_NAME="ppas-$EDB_SHORT_VERSION"
fi

# Set default registry namespace
if [ $REGISTRY_NAMESPACE_PROVIDED -eq 0 ]
then
	REGISTRY_NAMESPACE=edb
fi

if [ $UPDATE_COMPONENT_PROVIDED = 1 ]
then
	DeployContainer $UPDATE_CONTAINER	
fi

if [ $PUSH_IMAGE_IN_LOCAL_REPO = 1 -a $LOCAL_REGISTRY_PROVIDED = 0 ]
then
	LOCAL_REGISTRY=localhost:5000
fi 

if [ x"${RAR_INSTALL_PPAS}" = x"Y" -o x"${RAR_INSTALL_PPAS}" = x"y" ]
then

    MessageHeading "Configuring PostgresPlus Advanced Server Container.."

    if [ $DEPLOY_CONTAINER = 1 ]
    then
		DeployContainer edb-as
    fi

    if [ $PUSH_IMAGE_IN_LOCAL_REPO = 1 ]
    then
		MessageHeading "Pushing EDB Postgres Advanced Server Container to Local Repository.."
		PushImageToLocalRepository edb-as
    fi

    if [ $CREATE_TEMPLATE = 1 ]
    then
                CreateTemplate edb-as
    fi
fi

if [ x"${RAR_INSTALL_BART}" = x"Y" -o x"${RAR_INSTALL_BART}" = x"y" ]
then

    MessageHeading "Configuring EnterpriseDB BART Container.."

    if [ $DEPLOY_CONTAINER = 1 ]
    then
		DeployContainer edb-bart
    fi

    if [ $PUSH_IMAGE_IN_LOCAL_REPO = 1 ]
    then
		MessageHeading "Pushing EDB BART Container to Local Repository.."
                PushImageToLocalRepository edb-bart
    fi

    if [ $CREATE_TEMPLATE = 1 ]
    then
		CreateTemplate edb-bart
    fi
fi

if [ x"${RAR_INSTALL_PEM}" = x"Y" -o x"${RAR_INSTALL_PEM}" = x"y" ]
then

    MessageHeading "Configuring EnterpriseDB PEM Container.."

    if [ $DEPLOY_CONTAINER = 1 ]
    then
		DeployContainer pem
    fi

    if [ $PUSH_IMAGE_IN_LOCAL_REPO = 1 ]
    then
		MessageHeading "Pushing Postgres Enterprise Manager Container to Local Repository.."
                PushImageToLocalRepository pem
    fi

    if [ $CREATE_TEMPLATE = 1 ]
    then
                CreateTemplate pem
    fi
fi

if [ "${REMOVE_COMPONENT_NAME}" = "edb-as" ]
then
	if [ $REMOVE_COMPONENT_PROVIDED = 1 ]
	then

		MessageHeading "Removing PostgresPlus Advanced Server Container.."
		RemoveContainer edb-as
	fi	
fi

if [ "${REMOVE_COMPONENT_NAME}" = "edb-bart" ]
then
	if [ $REMOVE_COMPONENT_PROVIDED = 1 ]
        then

		MessageHeading "Removing EnterpriseDB BART Container.."
                RemoveContainer edb-bart
        fi

fi

if [ "${REMOVE_COMPONENT_NAME}" = "pem" ]
then
	if [ $REMOVE_COMPONENT_PROVIDED = 1 ]
        then

		MessageHeading "Removing EnterpriseDB PEM Container.."
                RemoveContainer pem
        fi
fi

if [ $START_REGISTRY = 1 ]
then
	StartRegistry
fi
