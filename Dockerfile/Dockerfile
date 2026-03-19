# Use the full Python 3.10 image for easier debugging and available tools
FROM python:3.10

# Set the working directory inside the container
WORKDIR /energat

# Copy the EnergAt source code folder from host to /energat inside container
COPY energat /energat

# Install OS-level dependency needed for numastat
RUN apt-get update && apt-get install -y --no-install-recommends \
    numactl \
    && rm -rf /var/lib/apt/lists/*

# Install bc for aggregate_energy.sh
RUN apt-get update && apt-get install -y --no-install-recommends \
    bc \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Install modified EnergAt from source (registers CLI command 'energat')
RUN python -m pip install .

# Optional: Set the container’s default command (useful for debugging)
#CMD ["/bin/bash"]
