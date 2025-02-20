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

#ifndef TORC_GENERIC_VISITORTYPE_HPP
#define TORC_GENERIC_VISITORTYPE_HPP

#include "torc/generic/Error.hpp"

namespace torc {
namespace generic {

/**
 * @brief A base class for Visitor
 *
 * This is the base class for Visitor template. This class is used to provide a concrete handle of
 * an inoutVisitor to a visitable class. This class therefore does not contain any methods other
 * than a (protected) constructor and a destructor.
 */
class BaseVisitor {
protected:
	BaseVisitor();

public:
	virtual
	~BaseVisitor() throw ();

private:
	BaseVisitor(const BaseVisitor&);
	BaseVisitor& operator =(const BaseVisitor&);
};

/**
 * @brief An acyclic inoutVisitor implementation
 *
 * The VisitorType template acts as a template that can be derived by clients to add extrinsic
 * virtual functions on class hierarchies. This is useful in situations where the user does not
 * have direct handle to a derived class, but has a pointer/reference to a base class. This class
 * defines a polymorphic method visit() that can be used to get a handle to the actual derived
 * object and can therefore be programmed to perform arbitrary operations on it using public
 * methods specific to the derived class object. For more information on the Visitor design pattern
 * see: http://en.wikipedia.org/wiki/Visitor_pattern
 * The inoutVisitor implementation in EOM follows the acyclic inoutVisitor implementation detailed
 * in Andrei Alexandrescu's <i>Modern C++ Design</i>.
 */
template <typename _Tp> class VisitorType : virtual public BaseVisitor {
protected:
	explicit VisitorType();

public:
	virtual ~VisitorType() throw ();

	/**
	 * Visit the target object. This will typically be a derived leaf type.
	 *
	 * @param[in,out] client A reference to the target object
	 * @exception Error Exception generated by any of the functions called from inside visit()
	 */
	virtual void visit(_Tp& client) throw (Error) = 0;

};

template <typename _Tp> VisitorType<_Tp>::VisitorType() {}

template <typename _Tp> VisitorType<_Tp>::~VisitorType() throw () {}

template <typename _Tp> void runVisitor(_Tp& inoutVisited, BaseVisitor& inoutVisitor)
	throw (Error) {
	typedef VisitorType<_Tp> ConcreteVisitor;

	if(ConcreteVisitor *p = dynamic_cast<ConcreteVisitor *>(&inoutVisitor)) {
		try {
			p->visit(inoutVisited);
		} catch(Error& e) {
			e.setCurrentLocation(__FUNCTION__, __FILE__, __LINE__);
			throw;
		}
		return;
	}
	//TBD::Error?Fallback?
	return;
}

} // namespace generic
} // namespace torc

#endif // TORC_GENERIC_VISITORTYPE_HPP
