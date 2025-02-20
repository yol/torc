// Torc - Copyright 2011-2013 University of Southern California.  All Rights Reserved.
// $HeadURL$
// $Id$

// This program is free software: you can redistribute it and/or modify it under the terms of the 
// GNU General Public License as published by the Free Software Foundation, either version 3 of the 
// License, or (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; 
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See 
// the GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License along with this program.  If 
// not, see <http://www.gnu.org/licenses/>.

/// \file
/// \brief Unit test for the Bitstream class.

#include <boost/test/unit_test.hpp>
#include "torc/bitstream/Bitstream.hpp"
#include "torc/common/DeviceDesignator.hpp"
#include "torc/common/DirectoryTree.hpp"
#include <fstream>
#include <iostream>

namespace torc {
namespace bitstream {

BOOST_AUTO_TEST_SUITE(bitstream)


/// \brief Unit test for the Bitstream class.
BOOST_AUTO_TEST_CASE(BitstreamUnitTest) {

	// build the file paths
	boost::filesystem::path executablePath = torc::common::DirectoryTree::getExecutablePath();
	boost::filesystem::path generatedPath = 
		executablePath / "regression" / "BitstreamUnitTest.generated.bit";
	boost::filesystem::path referencePath = 
		executablePath / "torc" / "bitstream" / "Virtex5UnitTest.reference.bit";

	// read the bitstream
	std::fstream fileStream(referencePath.string().c_str(), std::ios::binary | std::ios::in);
	BOOST_REQUIRE(fileStream.good());
	Bitstream bitstream;
	bitstream.readHeader(fileStream);
	bitstream.cleanDateAndTime();

	// write the bitstream header to the console
	std::cout << bitstream << std::endl;
	std::string deviceName = bitstream.getDeviceName();
	torc::common::DeviceDesignator deviceDesignator(deviceName);
	std::cout << "family is " << deviceDesignator.getFamily() << std::endl;

}

BOOST_AUTO_TEST_SUITE_END()

} // namespace bitstream
} // namespace torc
