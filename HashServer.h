#pragma once

#include "httplib.h"
#include "CudaHeader.cuh";

#include <mutex>

class HashServer
{
	
	const unsigned int API_SERVICE_PORT{ 8080 };
	httplib::Server server;
	
	std::mutex _lockHashContext;
	CudaHashContext* oclHash{ nullptr };
	CudaHashContext::HashChallenge _Solve(std::string input, unsigned int zeros);
	bool _DefineRoutes();

public:

	HashServer();
	~HashServer();

	bool Launch();

};

