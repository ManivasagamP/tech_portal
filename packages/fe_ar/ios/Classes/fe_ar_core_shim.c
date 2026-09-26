// Compiles the shared C core (packages/fe_ar/src) into the pod. A relative
// include, the pattern of Flutter's FFI plugin template: CocoaPods won't take
// source files from outside the pod directory, and Flutter symlinks the whole
// package, so ../../src resolves in the app's build.
#include "../../src/fe_ar_core.c"
