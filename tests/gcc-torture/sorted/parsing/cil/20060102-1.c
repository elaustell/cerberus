#include "cerberus.h"
/* Generated by CIL v. 1.7.3 */
/* print_CIL_Input is false */

extern void abort() ;
int f(int x ) 
{ 


  {
  return (x >> (sizeof(x) * 8UL - 1UL) ? -1 : 1);
}
}
int volatile   one  =    1;
int main(void) 
{ 
  int tmp ;
  int tmp___0 ;

  {
  tmp = f(one);
  tmp___0 = f(- one);
  if (tmp == tmp___0) {
    abort();
  }
  return (0);
}
}
