[
  {
    "name": "efs-init",
    "image": "public.ecr.aws/docker/library/busybox:latest",
    "essential": false,
    "cpu": 64,
    "memoryReservation": 64,
    "command": ["sh","-lc","set -e; mkdir -p /home/runner/_runner /home/runner/work; printf '[safe]\\n\\tdirectory = *\\n' > /home/runner/.gitconfig; chmod 0644 /home/runner/.gitconfig"],
    "mountPoints": [
      {
        "containerPath": "${container_path}",
        "sourceVolume": "${source_volume_name}",
        "readOnly": false
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${log_group_name}",
        "awslogs-region": "${aws_region}",
        "awslogs-stream-prefix": "efs-init"
      }
    }
  },
%{ if enable_dind }
  {
    "name": "docker",
    "image": "docker:28-dind",
    "cpu": 768,
    "memory": 1536,
    "essential": false,
    "privileged": true,
    "environment": [
      {
        "name": "DOCKER_TLS_CERTDIR",
        "value": ""
      }
    ],
    "command": [
      "--host=tcp://0.0.0.0:2375",
      "--tls=false",
      "--storage-driver=overlay2"
    ],
    "healthCheck": {
      "command": ["CMD-SHELL","docker info >/dev/null 2>&1 || exit 1"],
      "interval": 30,
      "timeout": 5,
      "retries": 5,
      "startPeriod": 90
    },
    "mountPoints": [
      {
        "containerPath": "/home/runner",
        "sourceVolume": "${source_volume_name}",
        "readOnly": false
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${log_group_name}",
        "awslogs-region": "${aws_region}",
        "awslogs-stream-prefix": "dind"
      }
    }
  },
%{ endif }
  {
    "name": "runner",
    "dependsOn": [
      { 
        "containerName": "efs-init",
        "condition": "COMPLETE"
      }
%{ if enable_dind }
      ,
      { 
        "containerName": "docker",
        "condition": "HEALTHY"
      }
%{ endif }
    ],
    "image": "${aws_account_id}.dkr.ecr.${aws_region}.amazonaws.com/${runner_image}",
    "cpu": 512,
    "memory": 1536,
    "essential": true,
    "privileged": ${runner_privileged},
    "user": "0:0",
    "environment": [
      { 
        "name": "RUNNER_SCOPE", 
        "value": "${runner_scope}" 
      },
      { 
        "name": "ORG_NAME", 
        "value": "${org_name}"
      },
      {
        "name": "RUNNER_ORG",
        "value": "${org_name}"
      },
      {
        "name": "RUNNER_NAME",
        "value": "${runner_name_prefix}"
      },
      {
        "name": "RUNNER_HOME",
        "value": "/runner-data"
      },
      { 
        "name": "RUNNER_GROUP", 
        "value": "Default"
      },
      {
        "name": "LABELS",
        "value": "${runner_labels}"
      },
      {
        "name": "RUNNER_LABELS",
        "value": "${runner_labels}"
      },
      {
        "name": "RUNNER_WORKDIR",
        "value": "/home/runner/work" 
      },
      { 
        "name": "CONFIGURED_ACTIONS_RUNNER_FILES_DIR",
        "value": "/home/runner/_runner" 
      },
      { 
        "name": "RUNNER_ALLOW_RUNASROOT", 
        "value": "1" 
      },
      { 
        "name": "GIT_CONFIG_GLOBAL", 
        "value": "/home/runner/.gitconfig"
      },
      { 
        "name": "DISABLE_AUTOMATIC_DEREGISTRATION", 
        "value": "true" 
      },
%{ if enable_dind }
      {
        "name": "DOCKER_HOST",
        "value": "tcp://127.0.0.1:2375"
      },
%{ endif }
      {
        "name": "TAR_OPTIONS",
        "value": "--no-same-owner"
      },
      { 
        "name":"ACTIONS_RUNNER_DEBUG",
        "value":"true"
      },
      { 
        "name":"ACTIONS_STEP_DEBUG",
        "value":"true"
      }
    ],
    "secrets": [
        {
          "name": "RUNNER_TOKEN",
           "valueFrom": "arn:aws:ssm:${aws_region}:${aws_account_id}:parameter/${runner_token_ssm_parameter_name}"
        }
    ],

    "mountPoints": [
        {
          "containerPath": "/home/runner",
          "sourceVolume": "${source_volume_name}",
          "readOnly": false
        },
        {
          "containerPath": "/runner",
          "sourceVolume": "runner-tmpfs",
          "readOnly": false
        },
        {
          "containerPath": "/runner-data",
          "sourceVolume": "runner-data-tmpfs",
          "readOnly": false
        }
      ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${log_group_name}",
        "awslogs-region": "${aws_region}",
        "awslogs-stream-prefix": "runner"
      }
    }
  }
]


