#include <iostream>
#include <thread>
#include "HashServer.h"

int main() {

	HashServer* hServer = new HashServer();
	std::thread([&hServer] {
		hServer->Launch();
	}).detach();

	std::this_thread::sleep_for(std::chrono::milliseconds(1000));
	std::cout << "Press enter to exit" << std::endl;
	std::cin.ignore();

	delete hServer;
	std::cout << "Done" << std::endl;

}