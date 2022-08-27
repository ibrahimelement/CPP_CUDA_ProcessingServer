
#include <iostream>

class CudaHashContext {

	// Constants
	const unsigned long int HASH_COUNT{ 1000 * 1000 * 10 }; // 10 million hashes
	const unsigned long int INPUT_SIZE{ 1024 }; // Max 1kb bytes for digest

	// Temp private store
	std::string strHashInput{ "" };
	unsigned int numZeros{ 0 };

	// Device oriented variables
	unsigned int* _dev_outFoundAtomic{ nullptr };
	unsigned int* _dev_outFoundIndex{ nullptr };
	unsigned char* _dev_hashOutput{ nullptr };
	unsigned char* _dev_nonceContainer{ nullptr };
	unsigned char* _dev_hashInput{ nullptr };
	unsigned int * _dev_hashInputSize{ nullptr };

	// Host variables
	unsigned char* _localHashOutput{ nullptr };

	// Private funcs
	bool _AllocateResources();
	bool _ResetDevice();

public:

	CudaHashContext();
	~CudaHashContext();

	static struct HashChallenge {
		bool success{ false };
		std::string correctOutput{ "" };
		unsigned long int numIterations{ 0 };
		std::string Serialize();
	};

	void Initialize();
	HashChallenge _ExecuteChallenge();
	HashChallenge SolveChallenge(std::string input, unsigned int zeros);
	
};

