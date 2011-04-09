program pvGet

%%#include "stdlib.h"
%%#include "epicsThread.h"
%%#include "epicsUnitTest.h"

option +s;

/* use literal C code to circumvent safe mode */
%%int shared = 0;

foreign shared;

int anon;
assign anon;

evflag stop;

#define MAX_PUT 40

entry {
    testPlan(108);
}

ss read_named {
    int named;
    connect named to "named_pv";
    int expected;

    state get {
        when (efTest(stop)) {
        } state done
        when (delay(0.2)) {
            expected = shared;
            pvGet(named, ASYNC);
            if (pvGetComplete(named)) {
                testOk(expected==named,
                    "immediate completion:      expected=%d==%d=named", expected, named);
            } else {
                testSkip(1, "no immediate completion");
            }
            epicsThreadSleep(0.1);
            if (pvGetComplete(named)) {
                testOk(expected==named,
                    "completion after delay:    expected=%d==%d=named", expected, named);
            } else {
                testSkip(1, "no completion after delay");
            }
        } state wait
    }
    state wait {
        when (pvGetComplete(named)) {
            testOk(expected==named,
                "completion after sync:     expected=%d==%d=named", expected, named);
        } state get
    }
    state done {
        when (FALSE) {} exit
    }
}

ss read_anon {
    int expected;

    state get {
        when (efTest(stop)) {
        } state done
        when (delay(0.2)) {
            expected = shared;
            pvGet(anon, ASYNC);
            if (pvGetComplete(anon)) {
                testOk(expected==anon,
                    "immediate completion:      expected=%d==%d=anon", expected, anon);
            } else {
                testSkip(1, "no immediate completion");
            }
            epicsThreadSleep(0.1);
            if (pvGetComplete(anon)) {
                testOk(expected==anon,
                    "completion after delay:    expected=%d==%d=anon", expected, anon);
            } else {
                testSkip(1, "no completion after delay");
            }
        } state wait
    }
    state wait {
        when (pvGetComplete(anon)) {
            testOk(expected==anon,
                "completion after sync:     expected=%d==%d=anon", expected, anon);
        } state get
    }
    state done {
        when (FALSE) {} exit
    }
}

ss read_named_sync {
    int named;
    connect named to "named_pv";
    int expected;

    state get {
        when (efTest(stop)) {
        } state done
        when (delay(0.2)) {
            expected = shared;
            pvGet(named, SYNC);
            testOk(expected==named,
                "synchronous get:           expected=%d==%d=named", expected, named);
            epicsThreadSleep(0.1);
            expected = shared;
            pvGet(named, SYNC);
            testOk(expected==named,
                "repeat get after delay:    expected=%d==%d=named", expected, named);
        } state wait
    }
    state wait {
        when () {
            testOk(expected==named,
                "after sync:                expected=%d==%d=named", expected, named);
        } state get
    }
    state done {
        when (FALSE) {} exit
    }
}

ss read_anon_sync {
    int expected;

    state get {
        when (efTest(stop)) {
        } state done
        when (delay(0.2)) {
            expected = shared;
            pvGet(anon, SYNC);
            testOk(expected==anon,
                "synchronous get:           expected=%d==%d=anon", expected, anon);
            epicsThreadSleep(0.1);
            expected = shared;
            pvGet(anon, SYNC);
            testOk(expected==anon,
                "repeat get after delay:    expected=%d==%d=anon", expected, anon);
        } state wait
    }
    state wait {
        when () {
            testOk(expected==anon,
                "after sync:                expected=%d==%d=anon", expected, anon);
        } state get
    }
    state done {
        when (FALSE) {} exit
    }
}

ss write {
    int out = 0;
    connect out to "named_pv";

    state run {
        when (out == MAX_PUT) {
            efSet(stop);
        } state done
        when (delay(0.07)) {
            shared = out;
            pvPut(out);
            anon = out;
            pvPut(anon);
            out++;
        } state run
    }
    state done {
        when (delay(0.4)) {
        } exit
    }
}

exit {
    testDone();
    exit(0);
}