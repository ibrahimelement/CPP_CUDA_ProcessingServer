#include "HashServer.h"
#include <chrono>

HashServer::HashServer() {
	this->oclHash = new CudaHashContext();
	this->oclHash->Initialize();
}

HashServer::~HashServer() {
	delete this->oclHash;
}

CudaHashContext::HashChallenge HashServer::_Solve(std::string challenge, unsigned int zeros) {

	CudaHashContext::HashChallenge hashRes;
	try {
		hashRes = oclHash->SolveChallenge(challenge, zeros);
	}
	catch (std::exception err) {
		std::cout << "Exception thrown: " << err.what() << std::endl;
	}

	return hashRes;
}

bool HashServer::_DefineRoutes() {

	std::mutex _lockHashContext();
	this->server.Get("/api/solve", [this](const httplib::Request& req, httplib::Response& res) {

		std::string resJson{ "" };

		this->_lockHashContext.lock();
		try {

			// Input validation
			std::string challenge = req.get_param_value("challenge");
			std::string zero = req.get_param_value("zeros");

			if (!zero.length()) {
				throw std::exception("No zeros provided");
			}
			if (!challenge.length()) {
				throw std::exception("No challenge provided");
			}
			char cZero = zero[0];
			if (!std::isdigit(cZero)) {
				throw std::exception("Invalid digit provided");
			}

			std::string strNumber{ "" };
			strNumber += cZero;
			unsigned int zeroCount = std::stoi(strNumber.c_str());
			if (zeroCount != 4 && zeroCount != 5) {
				throw std::exception("Invalid zero count input");
			}

			auto t1 = std::chrono::high_resolution_clock::now();
			CudaHashContext::HashChallenge hashRes = this->_Solve(challenge, zeroCount);
			auto t2 = std::chrono::high_resolution_clock::now();

			std::cout << "Done in: " << std::chrono::duration_cast<std::chrono::milliseconds>(t2 - t1).count() << std::endl;
			
			resJson = hashRes.Serialize();

		}
		catch (std::exception err) {
			this->_lockHashContext.unlock();
			std::cout << "Error: " << err.what() << std::endl;
			return res.set_content("Error", "text/plain");
		}

		this->_lockHashContext.unlock();

		return res.set_content(resJson, "application/json");

	});

	return true;
}

bool HashServer::Launch() {

	this->_DefineRoutes();

	std::cout << "Listening on: " << this->API_SERVICE_PORT << std::endl;
	this->server.listen(
		"127.0.0.1",
		this->API_SERVICE_PORT
	);

	return true;
}
