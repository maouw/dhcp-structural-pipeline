#ifndef SPHERICALMESH_CONVERT_TO_STRING_H
#define SPHERICALMESH_CONVERT_TO_STRING_H
#include <string>

namespace
{
  // since certain compilers don't support std::to_string yet
  template <typename T>
  std::string convert_to_string(const T& val)
  {
    std::ostringstream str;
    str << val;
    return str.str();
  }
}

#endif
