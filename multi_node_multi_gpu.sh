#https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start-nccl.html#nccl-start-base-cluster

##cuda and nvcc
nvidia-smi -q | head
nvcc --version
sudo systemctl enable nvidia-fabricmanager && sudo systemctl start nvidia-fabricmanager
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:$LD_LIBRARY_PATH

##gdrcopy
gdrcopy_sanity
gdrcopy_copybw
gdrcopy_copylat

#efa
curl -O https://efa-installer.amazonaws.com/aws-efa-installer-1.34.0.tar.gz
tar -xf aws-efa-installer-1.34.0.tar.gz && cd aws-efa-installer
sudo ./efa_installer.sh -y --mpi=openmpi4
sudo reboot
fi_info -p efa
fi_info -p efa -t FI_EP_RDM

#nccl
cd /opt
sudo git clone https://github.com/NVIDIA/nccl.git && cd nccl
sudo make -j src.build CUDA_HOME=/usr/local/cuda

#aws-ofi-nccl plugin
cd ~
sudo apt-get install libhwloc-dev
wget https://github.com/aws/aws-ofi-nccl/releases/download/v1.11.0-aws/aws-ofi-nccl-1.11.0-aws.tar.gz
tar -xf aws-ofi-nccl-1.11.0-aws.tar.gz && cd aws-ofi-nccl-1.11.0-aws
./configure --prefix=/opt/aws-ofi-nccl --with-mpi=/opt/amazon/openmpi \
--with-libfabric=/opt/amazon/efa \
--with-cuda=/usr/local/cuda \
--enable-platform-aws
export PATH=/opt/amazon/openmpi/bin/:$PATH
make && sudo make install

#Install the NCCL tests
cd ~
git clone https://github.com/NVIDIA/nccl-tests.git && cd nccl-tests
export LD_LIBRARY_PATH=/opt/amazon/efa/lib:$LD_LIBRARY_PATH
make MPI=1 MPI_HOME=/opt/amazon/openmpi NCCL_HOME=/opt/nccl/build CUDA_HOME=/usr/local/cuda

#Test your EFA and NCCL configuration
##instance metadata service - returns the instance metadata
##first requests a metadata token using curl
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` \
&& curl -H "X-aws-ec2-metadata-token: $TOKEN" –v http://169.254.169.254/latest/meta-data/local-ipv4 >> my-hosts

##After obtaining the token, the command uses it to make another curl request to retrieve the instance's local IPv4 address from the metadata service.
# curl http://169.254.169.254/latest/meta-data/local-ipv4 >> my-hosts

#This command is used to run distributed application using mpirun, which is part of the OpenMPI library. The specific application being run here is all_reduce_perf, a performance test from the NCCL (NVIDIA Collective Communications Library) tests.

# 1. mpirun : /opt/amazon/openmpi/bin/mpirun: This is the command to start an MPI (Message Passing Interface) program. The path specifies the location of the mpirun executable, which comes from OpenMPI.
# 2. Environment Variables (-x): 
    #-x FI_EFA_USE_DEVICE_RDMA=1: This environment variable enables RDMA (Remote Direct Memory Access) on the Elastic Fabric Adapter (EFA). RDMA provides high throughput and low latency for network communication, which is beneficial for high-performance computing applications.
    
    # -x LD_LIBRARY_PATH=/opt/nccl/build/lib:/usr/local/cuda/lib64:/opt/amazon/efa/lib:/opt/amazon/openmpi/lib:/opt/aws-ofi-nccl/lib:$LD_LIBRARY_PATH: This sets the LD_LIBRARY_PATH environment variable, which tells the system where to look for shared libraries. The paths specified include directories for NCCL, CUDA, EFA, OpenMPI, and AWS OFI (Open Fabric Interface) NCCL plugins, ensuring all necessary libraries are available.

    # -x NCCL_DEBUG=INFO: This enables detailed logging for NCCL. Setting this to INFO provides informational messages that can help with debugging and understanding the behavior of NCCL during the execution.

# 3. Hostfile and Process Allocation:
    # --hostfile my-hosts: Specifies the host file (my-hosts) that lists the nodes (EC2 instances) on which the MPI processes will run. Each line in this file typically contains the IP addresses or hostnames of the machines.

    # -n 8: This specifies the total number of MPI processes to run. Here, 8 processes will be launched across the nodes listed in the my-hosts file.

    # -N 8: Specifies the number of MPI processes to run on each node. In this case, 8 processes will be started on each node. Since -n and -N are the same, it implies that all processes will run on a single node.

# 4. MPI Configuration Parameters (--mca):
    # --mca pml ^cm: The PML (Point-to-Point Messaging Layer) component is responsible for handling point-to-point communication between MPI processes. The ^cm syntax means "exclude the cm component". This is typically done to force the use of another transport layer (such as TCP).

    # --mca btl tcp,self: The BTL (Byte Transfer Layer) components specify which network transport layers to use. Here, tcp (TCP/IP) and self (for communication within the same process) are specified.

    # --mca btl_tcp_if_exclude lo,docker0: This excludes the lo (loopback) and docker0 interfaces from being used by TCP for MPI communications. This ensures that only external network interfaces (likely EFA-enabled ones) are used.

# 5. Process Binding (--bind-to none):
    # --bind-to none: This option disables process binding, meaning that the MPI processes are not bound to specific CPU cores. This can be useful in certain scenarios where you want the operating system to manage CPU scheduling for processes dynamically.

# 6. Application-Specific Parameters:
    # $HOME/nccl-tests/build/all_reduce_perf: This is the path to the NCCL performance test binary (all_reduce_perf), which tests the performance of the AllReduce operation.

    # -b 8: Specifies the minimum size of the data buffer (in bytes) to be used for the AllReduce operation. Here, 8 bytes is the starting point.

    # -e 1G: Specifies the maximum size of the data buffer to be tested, with 1GB being the upper limit.

    # -f 2: Specifies the step factor by which the buffer size is increased in each test iteration. A value of 2 means that the buffer size will double with each iteration.

    # -g 1: Specifies the number of GPUs per node to use. Here, 1 GPU per node is used for the test.

    # -c 1: Specifies the number of MPI communicators to use. Here, only one communicator is used.

    # -n 100: Specifies the number of iterations to run for each buffer size. In this case, the AllReduce operation will be performed 100 times for each buffer size.


#1 GPU Test
/opt/amazon/openmpi/bin/mpirun \
-x FI_EFA_USE_DEVICE_RDMA=1 \
-x LD_LIBRARY_PATH=/opt/nccl/build/lib:/usr/local/cuda/lib64:/opt/amazon/efa/lib:/opt/amazon/openmpi/lib:/opt/aws-ofi-nccl/lib:$LD_LIBRARY_PATH \
-x NCCL_DEBUG=DEBUG \
--hostfile my-hosts -n 8 -N 8 \
--mca pml ^cm --mca btl tcp,self --mca btl_tcp_if_exclude lo,docker0 --bind-to none \
$HOME/nccl-tests/build/all_reduce_perf -b 8 -e 1G -f 2 -g 1 -c 1 -n 100

#8 GPU Test

# 1. Adjust the Hostfile and Process Allocation:
# Since all 8 GPUs are on a single machine, you don't need to specify multiple hosts. You can use a simple host file or even omit the host file and specify everything directly in the command.

# 2. Set the Number of Processes:
# You should launch 8 MPI processes, one for each GPU. The -n and -N parameters will be set to 8.

# 3. Binding Processes to GPUs:
# Ensure each MPI process is bound to a different GPU. This can be handled by the CUDA_VISIBLE_DEVICES environment variable. -x CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7: This environment variable ensures that each MPI process can see all 8 GPUs. Each process will automatically select a different GPU to run on.

/opt/amazon/openmpi/bin/mpirun \
-x FI_EFA_USE_DEVICE_RDMA=1 \
-x LD_LIBRARY_PATH=/opt/nccl/build/lib:/usr/local/cuda/lib64:/opt/amazon/efa/lib:/opt/amazon/openmpi/lib:/opt/aws-ofi-nccl/lib:$LD_LIBRARY_PATH \
-x NCCL_DEBUG=DEBUG \
-x CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7 \
-n 8 -N 8 \
--mca pml ^cm --mca btl tcp,self --mca btl_tcp_if_exclude lo,docker0 --bind-to none \
$HOME/nccl-tests/build/all_reduce_perf -b 8 -e 1G -f 2 -g 1 -c 1 -n 100
