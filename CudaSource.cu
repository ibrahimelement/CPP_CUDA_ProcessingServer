#include "CudaHeader.cuh"

#include <iostream>
#include <string>
#include <stdio.h>
#include <mutex>
#include <atomic>

#include "cuda_runtime.h"
#include "device_launch_parameters.h"

#include "SHA256.cuh"
#include "json11.h"

__device__ bool checkZeroPadding(unsigned char* sha, uint8_t difficulty) {

	bool isOdd = difficulty % 2 != 0;
	uint8_t max = (difficulty / 2) + 1;

	/*
		Odd : 00 00 01 need to check 0 -> 2
		Even : 00 00 00 1 need to check 0 -> 3
		odd : 5 / 2 = 2 => 2 + 1 = 3
		even : 6 / 2 = 3 => 3 + 1 = 4
	*/
	for (uint8_t cur_byte = 0; cur_byte < max; ++cur_byte) {
		uint8_t b = sha[cur_byte];
		if (cur_byte < max - 1) { // Before the last byte should be all zero
			if (b != 0) return false;
		}
		else if (isOdd) {
			if (b > 0x0F || b == 0) return false;
		}
		else if (b <= 0x0f) return false;

	}

	return true;

}

__device__ uint8_t nonce_to_str(uint64_t nonce, unsigned char* out) {
	uint64_t result = nonce;
	uint8_t remainder;
	uint8_t nonce_size = nonce == 0 ? 1 : floor(log10((double)nonce)) + 1;
	uint8_t i = nonce_size;
	while (result >= 10) {
		remainder = result % 10;
		result /= 10;
		out[--i] = remainder + '0';
	}

	out[0] = result + '0';
	i = nonce_size;
	out[i] = 0;
	return i;
}

void pre_sha256() {
	checkCudaErrors(cudaMemcpyToSymbol(dev_k, host_k, sizeof(host_k), 0, cudaMemcpyHostToDevice));
}

__global__ void HashKernel(unsigned long int hashTotal, BYTE* hashInput, unsigned int numZero, unsigned int inputSize, BYTE* hashOutput, BYTE* nonceContainer, unsigned int* hashIndex, unsigned int* found)
{

	unsigned long int totalHashed = 0;
	unsigned char nonceTemp[12];

	for (unsigned long int i = blockIdx.x * blockDim.x + threadIdx.x;
		i < hashTotal && !(*found);
		i += blockDim.x * gridDim.x)
	{

		unsigned long int nonceContainerOffset = (i * 6);
		unsigned long int hashContainerOffset = (i * 32);

		size_t nonceSize = nonce_to_str(i, nonceTemp);

		totalHashed++;
		SHA256_CTX ctx;
		sha256_init(&ctx);
		sha256_update(&ctx, hashInput, inputSize);
		sha256_update(&ctx, nonceTemp, nonceSize);
		sha256_final(&ctx, hashOutput + hashContainerOffset);

		if (checkZeroPadding(hashOutput + hashContainerOffset, numZero) && atomicExch(found, 1) == 0) {
			*hashIndex = i;
			printf("FOUND! %d %d, hashOutput location: %d, nonce output location: %d\n", numZero, *hashIndex, hashContainerOffset, nonceContainerOffset);
		}

	}

}

CudaHashContext::CudaHashContext(){}
CudaHashContext::~CudaHashContext(){

	std::cout << "Deallocating resources" << std::endl;

	// Free device memory
	if (this->_dev_outFoundAtomic != nullptr) {
		cudaFree(this->_dev_outFoundAtomic);
	}
	if (this->_dev_outFoundIndex != nullptr) {
		cudaFree(this->_dev_outFoundIndex);
	}
	if (this->_dev_hashOutput != nullptr) {
		cudaFree(this->_dev_hashOutput);
	}
	if (this->_dev_nonceContainer != nullptr) {
		cudaFree(this->_dev_nonceContainer);
	}
	if (this->_dev_hashInput != nullptr) {
		cudaFree(this->_dev_hashInput);
	}

	// Free host memory
	if (this->_localHashOutput != nullptr) {
		delete this->_localHashOutput;
	}

	this->_ResetDevice();

}

bool CudaHashContext::_ResetDevice() {

	std::cout << "Resetting device" << std::endl;
	cudaError_t cudaStatus;
	cudaStatus = cudaDeviceReset();
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaDeviceReset failed!");
		return true;
	}

	return false;
}

bool CudaHashContext::_AllocateResources() {

	try {

		cudaError_t cudaStatus;
		cudaStatus = cudaSetDevice(0);
		if (cudaStatus != cudaSuccess) {
			fprintf(stderr, "cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			throw std::exception("Failed to allocated resources");
		}

		cudaStatus = cudaMalloc((void**)&this->_dev_outFoundAtomic, sizeof(unsigned int));
		if (cudaStatus != cudaSuccess) {
			fprintf(stderr, "cudaMalloc failed!");
			throw std::exception("Failed to allocate resources");
		}

		cudaStatus = cudaMalloc((void**)&this->_dev_outFoundIndex, sizeof(unsigned int));
		if (cudaStatus != cudaSuccess) {
			fprintf(stderr, "cudaMalloc failed!");
			throw std::exception("Failed to allocate resources");
		}

		cudaStatus = cudaMalloc((void**)&this->_dev_nonceContainer, sizeof(unsigned char) * this->HASH_COUNT * 6);
		if (cudaStatus != cudaSuccess) {
			fprintf(stderr, "cudaMalloc failed!");
			throw std::exception("Failed to allocate resources");
		}

		cudaStatus = cudaMalloc((void**)&this->_dev_hashOutput, this->HASH_COUNT * sizeof(BYTE) * 32);
		if (cudaStatus != cudaSuccess) {
			fprintf(stderr, "cudaMalloc failed!");
			throw std::exception("Failed to allocate resources");
		}

		cudaStatus = cudaMalloc((void**)&this->_dev_hashInput, this->INPUT_SIZE);
		if (cudaStatus != cudaSuccess) {
			fprintf(stderr, "cudaMalloc failed!");
			throw std::exception("Failed to allocate resources");
		}

		cudaStatus = cudaMalloc((void**)&this->_dev_hashInputSize, sizeof(unsigned int));
		if (cudaStatus != cudaSuccess) {
			fprintf(stderr, "cudaMalloc failed!");
			throw std::exception("Failed to allocate resources");
		}

		pre_sha256();

		return true;

	}
	catch (std::exception err) {
		std::cout << "Critical error allocating resources: " << err.what() << std::endl;
	}
	
	return false;
}


void CudaHashContext::Initialize() {
	bool hasAllocated = this->_AllocateResources();
}

CudaHashContext::HashChallenge CudaHashContext::_ExecuteChallenge() {

	cudaError_t cudaStatus;

	HashKernel<<<1024, 32>>>(
		this->HASH_COUNT,
		this->_dev_hashInput,
		this->numZeros,
		this->strHashInput.size(),
		this->_dev_hashOutput,
		this->_dev_nonceContainer,
		this->_dev_outFoundIndex,
		this->_dev_outFoundAtomic
	);

	// Check for any errors launching the kernel
	cudaStatus = cudaGetLastError();
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "addKernel launch failed: %s\n", cudaGetErrorString(cudaStatus));
		throw std::exception("Launched failed");
	}

	// cudaDeviceSynchronize waits for the kernel to finish, and returns
	// any errors encountered during the launch.
	cudaStatus = cudaDeviceSynchronize();
	if (cudaStatus != cudaSuccess) {
		fprintf(stderr, "cudaDeviceSynchronize returned error code %d after launching addKernel!\n", cudaStatus);
		throw std::exception("Failed to syncronize with device");
	}

	// Copy output values
	HashChallenge hashRes;
	unsigned char* hostDigestSolution = new unsigned char[32];
	unsigned int* hasFoundSolution = new unsigned int;
	unsigned int* solutionIndex = new unsigned int;

	cudaMemcpy(
		hasFoundSolution,
		this->_dev_outFoundAtomic,
		sizeof(unsigned int),
		cudaMemcpyDeviceToHost
	);

	if (*hasFoundSolution) {
		
		hashRes.success = true;
		
		cudaMemcpy(
			solutionIndex,
			this->_dev_outFoundIndex,
			sizeof(unsigned int),
			cudaMemcpyDeviceToHost
		);

		cudaMemcpy(
			hostDigestSolution,
			this->_dev_hashOutput + (32 * (*solutionIndex)),
			32,
			cudaMemcpyDeviceToHost
		);

		hashRes.correctOutput = hash_to_string(
			hostDigestSolution
		);

		hashRes.numIterations = *solutionIndex;

	}

	delete[] hostDigestSolution;
	delete solutionIndex;
	delete hasFoundSolution;

	return hashRes;

}

CudaHashContext::HashChallenge CudaHashContext::SolveChallenge(std::string input, unsigned int zeros) {

	// Clear buffers from prior runs
	cudaMemset(
		this->_dev_hashInput,
		0,
		this->INPUT_SIZE
	);
	cudaMemset(
		this->_dev_outFoundIndex,
		0,
		sizeof(unsigned int)
	);
	cudaMemset(
		this->_dev_outFoundAtomic,
		0,
		sizeof(unsigned int)
	);


	// Copy over new input data
	cudaMemcpy(
		this->_dev_hashInput,
		input.c_str(),
		input.size(),
		cudaMemcpyHostToDevice
	);
	cudaMemset(
		this->_dev_hashInputSize,
		input.length(),
		sizeof(unsigned int)
	);

	this->strHashInput = input;
	this->numZeros = zeros;

	HashChallenge res = this->_ExecuteChallenge();

	return res;
}

std::string CudaHashContext::HashChallenge::Serialize() {

	json11::Json obj = json11::Json::object({
		{"success", this->success},
		{"output", this->correctOutput},
		{"postfix", (int)this->numIterations}
	});

	return obj.dump();

}