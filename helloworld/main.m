//
//  main.m
//  A main module for starting Python projects under iOS.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <Python.h>
#include <dlfcn.h>


int main(int argc, char *argv[]) {
    int ret = 0;
    unsigned int i;
    NSString *tmp_path;
    NSString *python_home;
    NSString *python_path;
    wchar_t *wpython_home;
    const char* nslog_script;
    wchar_t** python_argv;
    PyObject *module;
    PyObject *runpy;
    PyObject *runmodule;
    PyObject *runargs;
    PyObject *result;

    @autoreleasepool {

        NSString * resourcePath = [[NSBundle mainBundle] resourcePath];

        // Special environment to prefer .pyo; also, don't write bytecode
        // because the process will not have write permissions on the device.
        putenv("PYTHONOPTIMIZE=1");
        putenv("PYTHONDONTWRITEBYTECODE=1");
        putenv("PYTHONUNBUFFERED=1");

        // Set the home for the Python interpreter
        python_home = [NSString stringWithFormat:@"%@/Library/Python", resourcePath, nil];
        NSLog(@"PythonHome is: %@", python_home);
        wpython_home = Py_DecodeLocale([python_home UTF8String], NULL);
        Py_SetPythonHome(wpython_home);

        // Set the PYTHONPATH
        python_path = [NSString stringWithFormat:@"PYTHONPATH=%@/Library/Application Support/com.example.helloworld/app:%@/Library/Application Support/com.example.helloworld/app_packages", resourcePath, resourcePath, nil];
        NSLog(@"PYTHONPATH is: %@", python_path);
        putenv((char *)[python_path UTF8String]);

        // iOS provides a specific directory for temp files.
        tmp_path = [NSString stringWithFormat:@"TMP=%@/tmp", resourcePath, nil];
        putenv((char *)[tmp_path UTF8String]);

        NSLog(@"Initializing Python runtime...");
        Py_Initialize();

        // Set the name of the python NSLog bootstrap script
        nslog_script = [
            [[NSBundle mainBundle] pathForResource:@"Library/Application Support/com.example.helloworld/app_packages/nslog"
                                            ofType:@"py"] cStringUsingEncoding:NSUTF8StringEncoding];

        if (nslog_script == NULL) {
            NSLog(@"Unable to locate NSLog bootstrap script.");
            exit(-2);
        }

        // Construct argv for the interpreter
        python_argv = PyMem_RawMalloc(sizeof(wchar_t*) * argc);

        python_argv[0] = Py_DecodeLocale("helloworld", NULL);
        for (i = 1; i < argc; i++) {
            python_argv[i] = Py_DecodeLocale(argv[i], NULL);
        }

        PySys_SetArgv(argc, python_argv);

        // If other modules are using threads, we need to initialize them.
        PyEval_InitThreads();

        @try {
            NSLog(@"Installing Python NSLog handler...");
            FILE* fd = fopen(nslog_script, "r");
            if (fd == NULL) {
                ret = 1;
                NSLog(@"Unable to open nslog.py; abort.");
            } else {
                ret = PyRun_SimpleFileEx(fd, nslog_script, 1);
                fclose(fd);
                if (ret != 0) {
                    NSLog(@"Unable to install Python NSLog handler; abort.");
                } else {
//                    // Start the app module
//                    NSLog(@"Running 'helloworld'...");
//
//                    runpy = PyImport_ImportModule("runpy");
//                    if (runpy == NULL) {
//                        NSLog(@"Could not import runpy module");
//                        exit(-1);
//                    }
//
//                    runmodule = PyObject_GetAttrString(runpy, "_run_module_as_main");
//                    if (runpy == NULL) {
//                        NSLog(@"Could not access runpy._run_module_as_main");
//                        exit(-1);
//                    }
//
//                    module = PyUnicode_FromWideChar(python_argv[0], wcslen(python_argv[0]));
//                    if (runpy == NULL) {
//                        NSLog(@"Could not convert module name to unicode");
//                        exit(-1);
//                    }
//
//                    runargs = Py_BuildValue("(Oi)", module, 0);
//                    if (runpy == NULL) {
//                        NSLog(@"Could not create arguments for runpy._run_module_as_main");
//                        exit(-1);
//                    }
//
//                    result = PyObject_Call(runmodule, runargs, NULL);
//                    if (result == NULL) {
//                        NSLog(@"Application quit abnormally!");
//                        PyErr_Print();
//                    }

                    // In a normal iOS application, the following line is what
                    // actually runs the application. It requires that the
                    // Objective-C runtime environment has a class named
                    // "PythonAppDelegate". This project doesn't define
                    // one, because Objective-C bridging isn't something
                    // Python does out of the box. You'll need to use
                    // a library like Rubicon-ObjC [1], Pyobjus [2] or
                    // PyObjC [3] if you want to run an *actual* iOS app.
                    // [1] http://pybee.org/rubicon
                    // [2] http://pyobjus.readthedocs.org/
                    // [3] https://pythonhosted.org/pyobjc/
                    UIApplicationMain(argc, argv, nil, @"PythonAppDelegate");
                }
            }
        }
        @catch (NSException *exception) {
            NSLog(@"Python runtime error: %@", [exception reason]);
        }
        @finally {
            Py_Finalize();
        }

        PyMem_RawFree(wpython_home);
        if (python_argv) {
            for (i = 0; i < argc; i++) {
                PyMem_RawFree(python_argv[i]);
            }
            PyMem_RawFree(python_argv);
        }
        NSLog(@"Leaving...");
    }

    exit(ret);
    return ret;
}
