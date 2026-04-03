# ADLabV2 Ansible control node
# Runs ansible-playbook against lab VMs over SSH.
# Build: docker-compose -f docker/docker-compose.yml build
# Run:   docker-compose -f docker/docker-compose.yml run ansible ansible-playbook site.yml

FROM python:3.12-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-client \
        sshpass \
    && rm -rf /var/lib/apt/lists/*

# Install Ansible and required collections
RUN pip install --no-cache-dir \
        ansible-core==2.17.* \
        pywinrm             # kept for any fallback WinRM tasks

# Install Galaxy collections
RUN ansible-galaxy collection install \
        ansible.windows:>=2.3.0 \
        community.windows:>=2.2.0 \
        community.general:>=8.0.0

WORKDIR /ansible

# Default entrypoint — override CMD for specific playbooks
ENTRYPOINT ["ansible-playbook"]
CMD ["site.yml"]
