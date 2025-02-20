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
/// \brief Regression test for Heuristic class.

#include <boost/test/unit_test.hpp>
#include "torc/router/PathFinderHeuristic.hpp"

namespace torc {
namespace router {

BOOST_AUTO_TEST_SUITE(router)

/// \brief Unit test for the PathFinderHeuristic.
BOOST_AUTO_TEST_CASE(PathFinderHeuristic) {

	BOOST_CHECK_EQUAL(1 == 1, true);
	
}

BOOST_AUTO_TEST_SUITE_END()

} // namespace router
} // namespace torc
