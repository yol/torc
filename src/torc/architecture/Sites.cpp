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
/// \brief Source for the Sites class.

#include "torc/architecture/Sites.hpp"
#include <iostream>

namespace torc {
namespace architecture {

	size_t Sites::readPackages(DigestStream& inStream) {
		// prepare to read from the stream
		size_t bytesReadOffset = inStream.getBytesRead();
		char scratch[1 << 10];			// scratch read buffer
		uint16_t nameLength = 0;		// length of tile type name
		PackageCount packageCount;		// number of packages
		PadCount padCount;				// number of pads
		SiteFlags siteFlags;			// site attribute flags
		SiteIndex siteIndex;			// pad site index

		// read the section header
		string sectionName;
		inStream.readSectionHeader(sectionName);
		/// \todo Throw a proper exception.
		if(sectionName != ">>>>Packages>>>>") throw -1;

		// initialize the package array
		inStream.read(packageCount);
		mPackages.setSize(packageCount);
		mOut() << "\tReading " << packageCount << " package" << (packageCount != 1 ? "s" : "") 
			<< " (";
		// loop through each package
		for(PackageIndex i; i < packageCount; i++) {
			// look up the current package
			Package& package = const_cast<Package&>(mPackages[i]);
			// read the package name
			inStream.read(nameLength);
			/// \todo Throw a proper exception.
			if(nameLength > sizeof(scratch)) throw -1;
			inStream.read(scratch, nameLength);
			scratch[nameLength] = 0;
			// update the package
			package.mName = scratch;
			mPackageNameToPackageIndex[scratch] = i;
			mOut() << scratch << (i + 1 < packageCount ? ", " : "");
			// read the pad count
			inStream.read(padCount);
			package.mPads.setSize(padCount);
			// loop through each pad
			for(PadCount j; j < padCount; j++) {
				// look up the current pad
				Pad& pad = const_cast<Pad&>(package.mPads[j]);
				// read the site index
				inStream.read(siteIndex);
				// read the site flags
				inStream.read(siteFlags);
				// read the pad name
				inStream.read(nameLength);
				/// \todo Throw a proper exception.
				if(nameLength > sizeof(scratch)) throw -1;
				inStream.read(scratch, nameLength);
				scratch[nameLength] = 0;
				// update the package pad
				pad.mSiteIndex = siteIndex;
				pad.mFlags = siteFlags;
				pad.mName = scratch;
				package.mPadNameToPadIndex[scratch] = xilinx::PadIndex(j);
			}
		}
		mOut() << ") ..." << std::endl;
 
		// return the number of bytes read
		return inStream.getBytesRead() - bytesReadOffset;
	}

	size_t Sites::readPrimitiveTypes(DigestStream& inStream) {
		// prepare to read from the stream
		size_t bytesReadOffset = inStream.getBytesRead();
		char scratch[1 << 10];			// scratch read buffer
		uint16_t nameLength = 0;		// length of site type name
		SiteTypeCount siteTypeCount;	// number of site types
		uint32_t elementCount;			// number of site elements
		PinCount pinCount;				// number of pins
		PinFlags pinFlags;				// pin attribute flags
		uint32_t elementIndex;			// connection element index
		uint32_t pinIndex;				// connection pin index

		// read the section header
		string sectionName;
		inStream.readSectionHeader(sectionName);
		/// \todo Throw a proper exception.
		if(sectionName != ">>>>PrimDefs>>>>") throw -1;

		// initialize the tile type array
		inStream.read(siteTypeCount);
		mSiteTypes.setSize(siteTypeCount);
		mOut() << "\tReading " << siteTypeCount << " site types..." << std::endl;
		// loop through each site type
		for(SiteTypeIndex i; i < siteTypeCount; i++) {
			// look up the current site definition
			PrimitiveDef& primitiveDef = const_cast<PrimitiveDef&>(mSiteTypes[i]);
			// read the site type name
			inStream.read(nameLength);
			/// \todo Throw a proper exception.
			if(nameLength > sizeof(scratch)) throw -1;
			inStream.read(scratch, nameLength);
			scratch[nameLength] = 0;
//mOut() << "\t\t" << i << ": " << scratch << std::endl;
//mOut().flush();
			// read the pin count
			inStream.read(pinCount);
			// update the site definition
			primitiveDef.mName = scratch;
			primitiveDef.mPins.setSize(pinCount);
			// loop through each pin
			for(PinCount j; j < pinCount; j++) {
				// look up the current pin
				PrimitivePin& primitivePin = const_cast<PrimitivePin&>(primitiveDef.mPins[j]);
				// read the pin flags
				inStream.read(pinFlags);
				// read the pin name
				inStream.read(nameLength);
				/// \todo Throw a proper exception.
				if(nameLength > sizeof(scratch)) throw -1;
				inStream.read(scratch, nameLength);
				scratch[nameLength] = 0;
				// update the site pin
				primitivePin.mFlags = pinFlags;
				primitivePin.mName = scratch;
				primitiveDef.mPinNameToPinIndex[scratch] = xilinx::PinIndex(j);
			}
			// read the number of site elements
			inStream.read(elementCount);
			// update the site definition
			primitiveDef.mElements.setSize(elementCount);
			// loop through each element
			for(uint32_t j = 0; j < elementCount; j++) {
				// look up the current element
				PrimitiveElement& element 
					= const_cast<PrimitiveElement&>(primitiveDef.mElements[j]);
				// read the element name
				inStream.read(nameLength);
				/// \todo Throw a proper exception.
				if(nameLength > sizeof(scratch)) throw -1;
				inStream.read(scratch, nameLength);
				scratch[nameLength] = 0;
				// update the element name
				element.mName = scratch;
//mOut() << primitiveDef.getName() << " - " << element.getName() << ":" << std::endl;
//mOut() << "    ";
				// read the BEL flag
				uint16_t isBel;
				inStream.read(isBel);
				// read the pin count
				inStream.read(pinCount);
				// update the element
				element.mIsBel = isBel != 0;
				element.mPins.setSize(pinCount);
				// loop through each pin
				for(PinCount k; k < pinCount; k++) {
					// look up the current pin
					PrimitiveElementPin& elementPin = 
						const_cast<PrimitiveElementPin&>(element.mPins[k]);
					// read the pin flags
					inStream.read(pinFlags);
					// read the pin name
					inStream.read(nameLength);
					/// \todo Throw a proper exception.
					if(nameLength > sizeof(scratch)) throw -1;
					inStream.read(scratch, nameLength);
					scratch[nameLength] = 0;
					// update the site pin
					elementPin.mElementPtr = &element;
//mOut() << elementPin.mElementPtr->getName() << "." << scratch << " ";
//if(elementPin.mElementPtr == 0) {
//	mOut() << "Element pin " << scratch << " has NULL element" << std::endl;
//	mOut().flush();
//}
					elementPin.mFlags = pinFlags;
					elementPin.mName = scratch;
					element.mPinNameToPinIndex[scratch] = xilinx::PinIndex(k);
				}
//mOut() << std::endl;
				// read the config count
				uint32_t cfgCount;
				inStream.read(cfgCount);
				// loop through each cfg value
//bool debug = cfgCount > 0;
//if(debug) mOut() << "\t\t\t" << j << " \"" << scratch << "\": ";
				for(uint32_t k = 0; k < cfgCount; k++) {
					// read the cfg value
					inStream.read(nameLength);
					/// \todo Throw a proper exception.
					if(nameLength > sizeof(scratch)) throw -1;
					inStream.read(scratch, nameLength);
					scratch[nameLength] = 0;
//if(debug) mOut() << scratch << " ";
					// update the cfg values
					element.mCfgs.insert(scratch);
				}
//if(debug) mOut() << std::endl;
			}
			// read the conn count
			uint32_t connCount;
			inStream.read(connCount);
//mOut() << primitiveDef.mName << ": " << connCount << std::endl;
			// update the site definition
			primitiveDef.mConnections.setSize(connCount);
			// loop through each conn
			const PrimitiveElementArray& elements = primitiveDef.getElements();
			for(uint32_t j = 0; j < connCount; j++) {
				// look up the current connection
				PrimitiveConnSharedPtr& connectionPtr = primitiveDef.mConnections[j];
				connectionPtr = boost::shared_ptr<PrimitiveConn>(new PrimitiveConn());
				PrimitiveConn& connection = const_cast<PrimitiveConn&>(*connectionPtr);
				// read the source count
				uint16_t sourceCount;
				inStream.read(sourceCount);
				/// \todo Throw a proper exception
				if(sourceCount != 1) throw -1;
				// read the source element and pin
				inStream.read(elementIndex);
				inStream.read(pinIndex);
				const PrimitiveElement* elementPtr = elements.begin() + elementIndex;
				PrimitiveElement& element = const_cast<PrimitiveElement&>(*elementPtr);
				const PrimitiveElementPinArray& pins = element.getPins();
				PrimitiveElementPin& pin = const_cast<PrimitiveElementPin&>(pins[pinIndex]);
				connection.mSourcePtr = &pin;
				const_cast<PrimitiveConnSharedPtr&>(pin.mPrimitiveConn) = connectionPtr;
				// read the sink count
				uint16_t sinkCount;
				inStream.read(sinkCount);
				// loop through each sink
				for(uint32_t k = 0; k < sinkCount; k++) {
					// read the sink element and pin
					inStream.read(elementIndex);
					inStream.read(pinIndex);
					elementPtr = elements.begin() + elementIndex;
					PrimitiveElement& element = const_cast<PrimitiveElement&>(*elementPtr);
					const PrimitiveElementPinArray& pins = element.getPins();
					PrimitiveElementPin& pin = const_cast<PrimitiveElementPin&>(pins[pinIndex]);
					connection.mSinks.push_back(&pin);
					const_cast<PrimitiveConnSharedPtr&>(pin.mPrimitiveConn) = connectionPtr;
				}
			}
//mOut() << primitiveDef.getName() << " - " << element.getName() << ":" << std::endl;
		}

		// return the number of bytes read
		return inStream.getBytesRead() - bytesReadOffset;
	}

	size_t Sites::readPrimitivePinMaps(DigestStream& inStream) {
		// prepare to read from the stream
		size_t bytesReadOffset = inStream.getBytesRead();
		uint16_t primitivePinMapCount = 0;	// number of pin maps
		PinCount pinCount;				// number of pins
		WireIndex wireIndex;			// pin index

		// read the section header
		string sectionName;
		inStream.readSectionHeader(sectionName);
		/// \todo Throw a proper exception.
		if(sectionName != ">>>>Pin Maps>>>>") throw -1;

		// initialize the site pin map array
		inStream.read(primitivePinMapCount);
		mPrimitivePinMaps.setSize(primitivePinMapCount);
		mOut() << "\tReading " << primitivePinMapCount << " primitive pin maps..." << std::endl;
		// loop through each pin map
		for(uint16_t i = 0; i < primitivePinMapCount; i++) {
			// read the pin count
			inStream.read(pinCount);
			mPrimitivePinMaps[i].setSize(pinCount);
			// get a reference to this map's pin array
			Array<const WireIndex>& pins = mPrimitivePinMaps[i];
			// loop through each pin
			for(PinCount j; j < pinCount; j++) {
				// look up a reference to the pin and discard the const trait
				WireIndex& pin = const_cast<WireIndex&>(pins[j]);
				// read the pin
				inStream.read(wireIndex);
				pin = wireIndex;
			}
		}

		// return the number of bytes read
		return inStream.getBytesRead() - bytesReadOffset;
	}

	size_t Sites::readSites(DigestStream& inStream) {
		// prepare to read from the stream
		size_t bytesReadOffset = inStream.getBytesRead();
		char scratch[1 << 10];			// scratch read buffer
		uint16_t nameLength = 0;		// length of tile type name
		SiteCount siteCount;			// number of sites
		SiteTypeIndex siteTypeIndex;	// site type index
		TileIndex tileIndex;			// site tile index
		SiteFlags flags;				// site flags
		uint16_t pinMap = 0;			// site pin map

		// read the section header
		string sectionName;
		inStream.readSectionHeader(sectionName);
		/// \todo Throw a proper exception.
		if(sectionName != ">>>>  Sites >>>>") throw -1;

		// initialize the site array
		inStream.read(siteCount);
		mSites.setSize(siteCount);
		mOut() << "\tReading " << siteCount << " sites..." << std::endl;
		// loop through each site
		for(SiteIndex i; i < siteCount; i++) {
			// read the site name
			inStream.read(nameLength);
			/// \todo Throw a proper exception.
			if(nameLength > sizeof(scratch)) throw -1;
			inStream.read(scratch, nameLength);
			scratch[nameLength] = 0;
			// read the site type index, tile index, flags, and pin map
			inStream.read(siteTypeIndex);
			inStream.read(tileIndex);
			inStream.read(flags);
			inStream.read(pinMap);
			// look up a reference for the site, and discard the const trait
			Site& site = const_cast<Site&>(mSites[i]);
			site = Site(scratch, mSiteTypes[siteTypeIndex], tileIndex, flags, 
				mPrimitivePinMaps[pinMap]);
			mSiteNameToSiteIndex[scratch] = i;
		}

		// return the number of bytes read
		return inStream.getBytesRead() - bytesReadOffset;
	}

} // namespace architecture
} // namespace torc
