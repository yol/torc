// Torc - Copyright 2013 University of Southern California.  All Rights Reserved.
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

/// \brief Class to encapsulate micro-bitstream library generation code for Virtex5 family

#ifndef VIRTEX5LIBGEN_HPP_
#define VIRTEX5LIBGEN_HPP_

#include "AssemblerLibGen.hpp"

namespace torc {
namespace bitstream {

	class Virtex5LibGen : public AssemblerLibGen {
	public:
		/// \brief Constructor
		Virtex5LibGen(string inDevice, path inHarnessFolder, path inXdlGenerationFolder) 
		    : AssemblerLibGen(inDevice, inHarnessFolder, inXdlGenerationFolder) {
	    	initialize();    
		}	
		/// \brief Destructor
		virtual ~Virtex5LibGen() { }

		/// \brief Returns map of coumpound settings
		static CompoundSettingMap getCompoundSettingsMap() {
			CompoundSettingMap compoundSettingMap;
			std::vector<std::string> acascregCompound;
			acascregCompound.push_back("AREG");
			compoundSettingMap["ACASCREG"] = acascregCompound;

			std::vector<std::string> bcascregCompound;
			bcascregCompound.push_back("BREG");
			compoundSettingMap["BCASCREG"] = bcascregCompound;

			return compoundSettingMap;
		}

		/// \brief Get a map from config setting to reference value
		std::map<string, string> getReferenceConfigMap() {
			std::map<string, string> referenceConfigMap;
			referenceConfigMap["LFSR_EN_SET"] = "SET";
			referenceConfigMap["TEST_SET_P"] = "SET";
			referenceConfigMap["MASK"] = "000000000000";
			referenceConfigMap["PATTERN"] = "000000000000";

			return referenceConfigMap;
		}

	protected:
		/// \brief Do architecture specific part of initialization
		void initialize();

	/// Virtual Functions
		/// \brief Returns true if site type is supported
	    virtual bool isSiteTypeSupported(const string &inSiteType);
		/// \brief Returns list of supported tiles.
		virtual std::vector<std::string> getTilesSupportedForPips();
		/// \brief Returns primiry primitive or Ramb site
		virtual std::string getRambPrimaryPrimitive() {
			return "RAMB36_EXP";
		}
		/// \brief Compress given bitstream file against reference bitstream file
		virtual void compressBitFile(path primaryFile, path referenceFile);
		/// \brief Get word offset from tile row and col
		virtual uint32_t getWordOffsetFromTileLocation(TileRow tileRow, TileCol tileCol, BitstreamSharedPtr inBitstreamPtr);
		/// \brief Populate primitive name to primitive structure map
	    virtual PrimitiveStructuresSharedPtrMap getPrimitiveNameToStructreMap();
		/// \brief Generate micro-bitstreams for memory elements like LUT in RAM mode
		virtual void generateMemoryMicroBitstream();

	protected:
	// Static members
		static const int sCrcWordIndex; ///< This have to be changed for different Family
		static const string sTilesSupportedForPips[]; ///< Array of supported routing tiles

	};
	
} //namepsace bitstream 
} // namespace torc

#endif // VIRTEX5LIBGEN_HPP_

