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
/// \brief Unit test for the Virtex7 class.

#include <boost/test/unit_test.hpp>
#include "torc/bitstream/Virtex7.hpp"
#include "torc/common/DirectoryTree.hpp"
#include "torc/common/Devices.hpp"
#include "torc/architecture/DDB.hpp"
#include "torc/common/DeviceDesignator.hpp"
#include "torc/bitstream/OutputStreamHelpers.hpp"
#include "torc/bitstream/build/DeviceInfoHelper.hpp"
#include "torc/common/TestHelpers.hpp"
#include <fstream>
#include <iostream>
#include <boost/filesystem.hpp>

namespace torc{
namespace bitstream{

BOOST_AUTO_TEST_SUITE(bitstream)

/// \brief Unit test for the Virtex7 class
BOOST_AUTO_TEST_CASE(Virtex7UnitTest){
	// enums tested:
	//		Epacket
	//		Efar
	boost::uint32_t mask;
	// type 1 packet subfield masks
	mask = Virtex7::ePacketMaskType + Virtex7::ePacketMaskOpcode 
		+ Virtex7::ePacketMaskType1Address + Virtex7::ePacketMaskType1Reserved 
		+ Virtex7::ePacketMaskType1Count;
	BOOST_CHECK_EQUAL(mask, 0xFFFFFFFFu);
	// type 2 packet subfield masks
	mask = Virtex7::ePacketMaskType + Virtex7::ePacketMaskOpcode 
		+ Virtex7::ePacketMaskType2Count;
	BOOST_CHECK_EQUAL(mask, 0xFFFFFFFFu);
	// frame address register subfield masks
	mask = Virtex7::eFarMaskBlockType + Virtex7::eFarMaskTopBottom + Virtex7::eFarMaskRow 
		+ Virtex7::eFarMaskMajor + Virtex7::eFarMaskMinor;
	BOOST_CHECK_EQUAL(mask, 0x03FFFFFFu);

	// members tested:
	//		Virtex7::sPacketTypeName and EPacketTypeName
	BOOST_CHECK_EQUAL(Virtex7::sPacketTypeName[0],							"[UNKNOWN TYPE 0]");
	BOOST_CHECK_EQUAL(Virtex7::sPacketTypeName[Virtex7::ePacketType1],		"TYPE1");
	BOOST_CHECK_EQUAL(Virtex7::sPacketTypeName[Virtex7::ePacketType2],		"TYPE2");
	BOOST_CHECK_EQUAL(Virtex7::sPacketTypeName[3],							"[UNKNOWN TYPE 3]");
	BOOST_CHECK_EQUAL(Virtex7::sPacketTypeName[4],							"[UNKNOWN TYPE 4]");
	BOOST_CHECK_EQUAL(Virtex7::sPacketTypeName[5],							"[UNKNOWN TYPE 5]");
	BOOST_CHECK_EQUAL(Virtex7::sPacketTypeName[6],							"[UNKNOWN TYPE 6]");
	BOOST_CHECK_EQUAL(Virtex7::sPacketTypeName[7],							"[UNKNOWN TYPE 7]");

	// members tested:
	//		Virtex7::sOpcodeName and EOpcode
	BOOST_CHECK_EQUAL(Virtex7::sOpcodeName[Virtex7::eOpcodeNOP],			"NOP");
	BOOST_CHECK_EQUAL(Virtex7::sOpcodeName[Virtex7::eOpcodeRead],			"READ");
	BOOST_CHECK_EQUAL(Virtex7::sOpcodeName[Virtex7::eOpcodeWrite],			"WRITE");
	BOOST_CHECK_EQUAL(Virtex7::sOpcodeName[Virtex7::eOpcodeReserved],		"RESERVED");

	// members tested:
	//		Virtex7::sRegisterName and ERegister
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterCRC],		"CRC");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterFAR],		"FAR");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterFDRI],		"FDRI");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterFDRO],		"FDRO");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterCMD],		"CMD");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterCTL0],		"CTL0");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterMASK],		"MASK");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterSTAT],		"STAT");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterLOUT],		"LOUT");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterCOR0],		"COR0");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterMFWR],		"MFWR");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterCBC],		"CBC");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterIDCODE],		"IDCODE");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterAXSS],		"AXSS");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterCOR1],		"COR1");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterWBSTAR],		"WBSTAR");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterTIMER],		"TIMER");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterBOOTSTS],	"BOOTSTS");
	BOOST_CHECK_EQUAL(Virtex7::sRegisterName[Virtex7::eRegisterCTL1],		"CTL1");

	// members tested:
	//		Virtex7::sCommandName and ECommand
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandNULL],			"NULL");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandWCFG],			"WCFG");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandMFW],			"MFW");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandLFRM],			"DGHIGH/LFRM");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandRCFG],			"RCFG");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandSTART],		"START");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandRCAP],			"RCAP");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandRCRC],			"RCRC");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandAGHIGH],		"AGHIGH");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandSWITCH],		"SWITCH");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandGRESTORE],		"GRESTORE");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandSHUTDOWN],		"SHUTDOWN");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandGCAPTURE],		"GCAPTURE");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandDESYNCH],		"DESYNCH");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandReserved],		"Reserved");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandIPROG],		"IPROG");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandCRCC],			"CRCC");
	BOOST_CHECK_EQUAL(Virtex7::sCommandName[Virtex7::eCommandLTIMER],		"LTIMER");


	// build the file paths
	boost::filesystem::path referencePath = torc::common::DirectoryTree::getExecutablePath()
		/ "torc" / "bitstream" / "Virtex7UnitTest.reference.bit";
	boost::filesystem::path generatedPath = torc::common::DirectoryTree::getExecutablePath()
		/ "regression" / "Virtex7UnitTest.generated.bit";

	// read the bitstream
	std::fstream fileStream(referencePath.string().c_str(), std::ios::binary | std::ios::in);
	BOOST_REQUIRE(fileStream.good());
	Virtex7 bitstream;
	bitstream.read(fileStream, false);
	// write the bitstream digest to the console
	std::cout << bitstream << std::endl;


	std::string designName = bitstream.getDesignName();
	std::string deviceName = bitstream.getDeviceName();
	std::string designDate = bitstream.getDesignDate();
	std::string designTime = bitstream.getDesignTime();
	torc::common::DeviceDesignator deviceDesignator(deviceName);
	std::cout << "family of " << deviceName << " is " << deviceDesignator.getFamily() << std::endl;

	// write the bitstream back out
	std::fstream outputStream(generatedPath.string().c_str(), std::ios::binary | std::ios::out);
	BOOST_REQUIRE(outputStream.good());
	bitstream.write(outputStream);
	outputStream.flush();

	// compare the reference and generated XDL
	BOOST_CHECK(torc::common::fileContentsAreEqual(generatedPath, referencePath));  
}  
















void testVirtex7Device(const std::string& inDeviceName, const boost::filesystem::path& inWorkingPath);

/// \brief Unit test for the Virtex7 class Frame Address Register mapping.
BOOST_AUTO_TEST_CASE(Virtex7FarUnitTest) {

	// look up the command line arguments
	int& argc = boost::unit_test::framework::master_test_suite().argc;
	char**& argv = boost::unit_test::framework::master_test_suite().argv;
	// make sure that we at least have the name under which we were invoked
	BOOST_REQUIRE(argc >= 1);
	// resolve symbolic links if applicable
	torc::common::DirectoryTree directoryTree(argv[0]);
#if 0	
	// iterate over the Artix7 devices
	{
		const torc::common::DeviceVector& devices = torc::common::Devices::getArtix7Devices();
		torc::common::DeviceVector::const_iterator dp = devices.begin();
		torc::common::DeviceVector::const_iterator de = devices.end();
		while(dp < de) {
			const std::string& device = *dp++;
			if(device.empty()) break;
//std::cout << "device " << ": " << device << std::endl;
			testVirtex7Device(device, torc::common::DirectoryTree::getWorkingPath());
		}
	}

	// iterate over the Kintex7 devices
	{
		const torc::common::DeviceVector& devices = torc::common::Devices::getKintex7Devices();
		torc::common::DeviceVector::const_iterator dp = devices.begin();
		torc::common::DeviceVector::const_iterator de = devices.end();
		while(dp < de) {
			const std::string& device = *dp++;
			if(device.empty()) break;
//std::cout << "device " << ": " << device << std::endl;
			testVirtex7Device(device, torc::common::DirectoryTree::getWorkingPath());
		}
	}

	// iterate over the Virtex7 devices
	{
		const torc::common::DeviceVector& devices = torc::common::Devices::getVirtex7Devices();
		torc::common::DeviceVector::const_iterator dp = devices.begin();
		torc::common::DeviceVector::const_iterator de = devices.end();
		while(dp < de) {
			const std::string& device = *dp++;
			if(device.empty()) break;
			// the Xilinx tools only generate debug bitstreams for a subset of Virtex7 devices
			if(device != "xc7v585t" && device != "xc7vx330t" && device != "xc7vx415t" 
				&& device != "xc7vx485t" && device != "xc7vx550t" && device != "xc7vx690t" 
				&& device != "xc7vx980t") continue;
//std::cout << "device " << ": " << device << std::endl;
			testVirtex7Device(device, torc::common::DirectoryTree::getWorkingPath());
		}
	}
#endif
	// iterate over the Zynq7000 devices
	{
		const torc::common::DeviceVector& devices = torc::common::Devices::getZynq7000Devices();
		torc::common::DeviceVector::const_iterator dp = devices.begin();
		torc::common::DeviceVector::const_iterator de = devices.end();
		while(dp < de) {
			const std::string& device = *dp++;
			if(device.empty()) break;
if(device != "xc7z045") continue;
//std::cout << "device " << ": " << device << std::endl;
			testVirtex7Device(device, torc::common::DirectoryTree::getWorkingPath());
		}
	}

}
  /*
        class TileTypeWidths {
        public:
                uint32_t mWidth[8];
                TileTypeWidths(uint32_t in0 = 0, uint32_t in1 = 0, uint32_t in2 = 0, uint32_t in3 = 0, 
                        uint32_t in4 = 0, uint32_t in5 = 0, uint32_t in6 = 0, uint32_t in7 = 0) {
                        int i = 0;
                        mWidth[i++] = in0; mWidth[i++] = in1; mWidth[i++] = in2; mWidth[i++] = in3;
                        mWidth[i++] = in4; mWidth[i++] = in5; mWidth[i++] = in6; mWidth[i++] = in7;
                }
                void clear(void) { for(int i = 0; i < 8; i++) mWidth[i] = 0; }
                uint32_t operator[] (int inIndex) const { return mWidth[inIndex]; }
        };
  */

void testVirtex7Device(const std::string& inDeviceName, const boost::filesystem::path& inWorkingPath) {

	// build the file paths
	boost::filesystem::path debugBitstreamPath = inWorkingPath / "torc" / "bitstream" / "regression";
	//boost::filesystem::path generatedPath = debugBitstreamPath / (inDeviceName + ".debug.bit");
	boost::filesystem::path referencePath = debugBitstreamPath / (inDeviceName + ".debug.bit");

	// read the bitstream
	std::fstream fileStream(referencePath.string().c_str(), std::ios::binary | std::ios::in);
	std::cerr << "Trying to read: " << referencePath << std::endl;
	BOOST_REQUIRE(fileStream.good());
	Virtex7 bitstream;
	bitstream.read(fileStream, false);
	// write the bitstream digest to the console
//	std::cout << bitstream << std::endl;


	typedef std::map<Virtex7::FrameAddress, Virtex7::FrameAddress> FrameAddressMap;
	FrameAddressMap fars;
	// determine the far count in every column
	Virtex7::const_iterator p = bitstream.begin();
	Virtex7::const_iterator e = bitstream.end();
	uint32_t header = VirtexPacket::makeHeader(VirtexPacket::ePacketType1, 
		 VirtexPacket::eOpcodeWrite, Virtex7::eRegisterLOUT, 1);
	while(p < e) {
		const VirtexPacket& packet = *p++;
		if(packet.getHeader() != header) continue;
		Virtex7::FrameAddress far = packet[1];
		Virtex7::FrameAddress base = far;
		base.mMinor = 0;
		fars[base] = std::max(fars[base], far);
	}
	// write out the maximum far for every column
	FrameAddressMap::const_iterator fp = fars.begin();
	FrameAddressMap::const_iterator fe = fars.end();
	while(fp != fe) {
		const FrameAddressMap::value_type& value = *fp++;
(void) value;
//		std::cerr << value.second << std::endl;
	}

	// initialize the bitstream frame maps
//	boost::filesystem::path deviceColumnsPath = inWorkingPath / "torc" / "bitstream" / "regression" 
//		/ (inDeviceName + ".cpp");
//	std::fstream deviceColumnsStream(deviceColumnsPath.string().c_str(), std::ios::out);
	bitstream.initializeDeviceInfo(inDeviceName);
	bitstream.initializeFrameMaps();


	// iterate through the packets, and extract all of the FARs
	Virtex7::FrameAddressToIndex farRemaining = bitstream.mFrameAddressToIndex;
	Virtex7::FrameAddressToIndex farVisited;
	{
		bool enabled = false;
		Virtex7::const_iterator p = bitstream.begin();
		Virtex7::const_iterator e = bitstream.end();
		uint32_t header = VirtexPacket::makeHeader(VirtexPacket::ePacketType1, 
				       VirtexPacket::eOpcodeWrite, Virtex7::eRegisterLOUT, 1);
		uint32_t enable = VirtexPacket::makeHeader(VirtexPacket::ePacketType1, 
				       VirtexPacket::eOpcodeWrite, Virtex7::eRegisterCMD, 1);
		while(p < e) {
			const VirtexPacket& packet = *p++;
			if(packet.getHeader() == enable) enabled = true;
			if(!enabled) continue;
			if(packet.getHeader() != header) continue;
			Virtex7::FrameAddress far = packet[1];
			farVisited[far] = 0;
			Virtex7::FrameAddressToIndex::iterator found = farRemaining.find(far);
			if(found != farRemaining.end()) {
				farRemaining.erase(found);
			} else {
				std::cerr << "missing " << far << " ";
			}
		}
	}
	{
		Virtex7::FrameAddressToIndex::const_iterator p = farRemaining.begin();
		Virtex7::FrameAddressToIndex::const_iterator e = farRemaining.end();
		while(p != e) {
			std::cerr << "remaining " << (*p++).first << " ";
		}
		std::cerr << std::endl;
	}
	// verify that we have visited all of the expected FARs and no others
	std::cout << "Device: " << inDeviceName << std::endl;
	std::cout << "Size of farRemaining: " << farRemaining.size() << std::endl;
	std::cout << "Size of farVisited: " << farVisited.size() << std::endl;
	BOOST_CHECK_EQUAL(farRemaining.size(), 0u);
	BOOST_CHECK_EQUAL(farVisited.size(), bitstream.mFrameAddressToIndex.size());

	// iterate through the debug bitstream packets, and extract all of the FARs
	// this isn't currently being used, but it may come in handy for debugging
	for(int half = 0; half < 2; half++) {
break;
		for(uint32_t row = 0; row < 2; row++) {
			typedef std::map<uint32_t, uint32_t> ColumnMaxFrame;
			ColumnMaxFrame maxFrames[Virtex7::eFarBlockTypeCount];
			Virtex7::const_iterator p = bitstream.begin();
			Virtex7::const_iterator e = bitstream.end();
			uint32_t header = VirtexPacket::makeHeader(VirtexPacket::ePacketType1, 
				 VirtexPacket::eOpcodeWrite, Virtex7::eRegisterLOUT, 1);
			while(p < e) {
				const VirtexPacket& packet = *p++;
				if(packet.getHeader() != header) continue;
				Virtex7::FrameAddress far = packet[1];
//				uint32_t far = packet[1];
//				std::cerr << Hex32(far) << " ";
				if(far.mTopBottom == half && far.mRow == row) { 
//					std::cerr << far << " ";
					ColumnMaxFrame::iterator i = maxFrames[far.mBlockType].find(far.mMajor);
					if(i == maxFrames[far.mBlockType].end()) {
						maxFrames[far.mBlockType][far.mMajor] = 0;
					} else {
						if(maxFrames[far.mBlockType][far.mMajor] < far.mMinor) 
							maxFrames[far.mBlockType][far.mMajor] = far.mMinor;
					}
				}
			}
			std::cerr << std::endl;
			uint32_t frameCount = 0;
			for(uint32_t i = 0; i < Virtex7::eFarBlockTypeCount; i++) {
				Virtex7::EFarBlockType blockType = Virtex7::EFarBlockType(i);
				uint32_t majorCount = maxFrames[blockType].size();
				for(uint32_t major = 0; major < majorCount; major++) {
					frameCount += maxFrames[blockType][major] + 1;
					std::cerr << blockType << "(" << major << "): " 
						<< (maxFrames[blockType][major] + 1) << " (" << frameCount << ")" 
							<< std::endl;
				}
			}
		}
	}

//	BOOST_REQUIRE_EQUAL(bitstream.mFrameAddressToIndex.size(), farVisited.size());
//	BOOST_REQUIRE_EQUAL(farRemaining.size(), 0u);
}

/// \brief Unit test for the Virtex7 frame reading.
BOOST_AUTO_TEST_CASE(Virtex7FramesUnitTest) {

	/// \todo This should work correctly with a partial bitstream but has not yet been tested.
	boost::filesystem::path bitstreamPath = torc::common::DirectoryTree::getExecutablePath() 
		/ "torc" / "bitstream" / "Virtex7UnitTest.reference.bit";
	std::fstream fileStream(bitstreamPath.string().c_str(), std::ios::binary | std::ios::in);
	BOOST_REQUIRE(fileStream.good());

	// read the header and determine the device family
	Virtex7 bitstream;
	bitstream.read(fileStream);
	bitstream.initializeDeviceInfo(bitstream.getDeviceName());
	bitstream.initializeFrameMaps();
	bitstream.readFramePackets();

}

/// \brief Unit test for the Virtex7 class
BOOST_AUTO_TEST_CASE(Virtex7WriteUnitTest){

	// build the file paths
	boost::filesystem::path referencePath = torc::common::DirectoryTree::getExecutablePath()
		/ "torc" / "bitstream" / "Virtex7UnitTest.reference.bit";
	boost::filesystem::path generatedPath = torc::common::DirectoryTree::getExecutablePath()
		/ "regression" / "Virtex7WriteUnitTest.generated.bit";

	// read the bitstream
	std::fstream fileStream(referencePath.string().c_str(), std::ios::binary | std::ios::in);
	BOOST_REQUIRE(fileStream.good());
	Virtex7 bitstream;
	bitstream.read(fileStream, false);
	// write the bitstream digest to the console
	std::cout << bitstream << std::endl;

	// initialize the frame information
	common::DeviceDesignator designator(bitstream.getDeviceName());
	bitstream.initializeDeviceInfo(designator.getDeviceName());
	bitstream.initializeFrameMaps();
	bitstream.readFramePackets();

	// write the bitstream back out
	std::fstream outputStream(generatedPath.string().c_str(), std::ios::binary | std::ios::out);
	BOOST_REQUIRE(outputStream.good());
/*
bitstream.getFrameBlocks().mBlock[0][50]->setDirty();
bitstream.getFrameBlocks().mBlock[0][1000]->setDirty();
bitstream.getFrameBlocks().mBlock[0][1001]->setDirty();
bitstream.getFrameBlocks().mBlock[0][1002]->setDirty();
bitstream.getFrameBlocks().mBlock[0][1003]->setDirty();
*/
bitstream.getFrameBlocks().mBlock[0][7661]->setDirty();
bitstream.updateFramePackets(Bitstream::eBitstreamTypePartialActive, 
	Bitstream::eFrameIncludeOnlyDirtyFrames);
	bitstream.write(outputStream);
	outputStream.flush();
	std::cout << bitstream << std::endl;

}  

#if 0
/// \brief Unit test for Zynq XDL frame lookup.
BOOST_AUTO_TEST_CASE(Zynq7000DebugUnitTest){
	// read both bitstreams
	std::fstream refFileStream("v7_routing.bit", std::ios::binary | std::ios::in);
	std::fstream genFileStream("v7_routing.custom.bit", std::ios::binary | std::ios::in);
	BOOST_REQUIRE(refFileStream.good());
	BOOST_REQUIRE(genFileStream.good());
	Virtex7 refBitstream;
	Virtex7 genBitstream;
	refBitstream.read(refFileStream, false);
	genBitstream.read(genFileStream, false);
	// initialize frame information
	common::DeviceDesignator designator(refBitstream.getDeviceName());
	refBitstream.initializeDeviceInfo(designator.getDeviceName());
	genBitstream.initializeDeviceInfo(designator.getDeviceName());
	refBitstream.initializeFrameMaps();
	genBitstream.initializeFrameMaps();
	refBitstream.readFramePackets();
	genBitstream.readFramePackets();
	// iterate through frame block types
	uint32_t index = 0;
	VirtexFrameBlocks& refFrameBlocks = refBitstream.getFrameBlocks();
	VirtexFrameBlocks& genFrameBlocks = genBitstream.getFrameBlocks();
	for(int i = 0; i < Bitstream::eBlockTypeCount; i++) {
		// look up the current frame sets
		VirtexFrameSet& refFrameSet = refFrameBlocks.mBlock[i];
		VirtexFrameSet& genFrameSet = genFrameBlocks.mBlock[i];
		// iterate through frame sets
		VirtexFrameSet::iterator rp = refFrameSet.begin();
		VirtexFrameSet::iterator re = refFrameSet.end();
		VirtexFrameSet::iterator gp = genFrameSet.begin();
		VirtexFrameSet::iterator ge = genFrameSet.end();
		while(rp < re && gp < ge) {
			// look up the current frames
			VirtexFrameSharedPtr refFrame = *rp++;
			VirtexFrameSharedPtr genFrame = *gp++;
			// look up the frame words
			uint32_t length = refFrame->getLength();
			typedef VirtexFrame::word_t word_t;
			const word_t* refWords = refFrame->getWords();
			const word_t* genWords = genFrame->getWords();
			// iterate through the words
			const word_t* refWordsEnd = refWords + length;
			while(refWords < refWordsEnd) {
				if(*refWords++ != *genWords++) {
					// convert the frame index to a frame address
					Virtex7::FrameAddress frameAddress = refBitstream.mFrameIndexToAddress[index];
					// we found a difference in this frame
					std::cout << "    Difference in frame index " << index << ": " 
						<< frameAddress << std::endl;
					// no need to continue inspecting the frame
					break;
				}
			}
			// increment the frame index
			index++;
		}
	}
	// look up the frame set for tile INT_R_X93Y83 [277,225]
	uint32_t beginBit;
	uint32_t endBit;
	uint32_t xdlRow = 277;
	uint32_t xdlCol = 225;
	uint32_t primaryXdlCol = refBitstream.getPrimaryXdlColumn(xdlRow, xdlCol);
	VirtexFrameBlocks frameBlocks = refBitstream.getXdlFrames(xdlRow, primaryXdlCol, beginBit, 
		endBit, 8);

	//for(xdlRow = 1; xdlRow < 365; xdlRow += 52) {
	//	for(xdlCol = 0; xdlCol < 267; xdlCol++) {
	//		//std::cout << "[" << xdlRow << "," << xdlCol << "]" << std::endl;
	//		VirtexFrameBlocks frameBlocks = refBitstream.getXdlFrames(xdlRow, xdlCol, beginBit, 
	//			endBit, 8);
	//	}
	//}
}
#endif

BOOST_AUTO_TEST_SUITE_END()


} //namespace bitstream
}//namespace torc
