/*
 * $Id: seqCommands.c,v 1.6 2001-02-16 21:45:16 norume Exp $
 *
 * DESCRIPTION: EPICS sequencer commands
 *
 * Author:  Eric Norum
 *
 * Experimental Physics and Industrial Control System (EPICS)
 *
 * Initial development by:
 *    Canadian Light Source
 *    107 North Road
 *    University of Saskatchewan
 *    Saskatoon, Saskatchewan, CANADA
 *    cls.usask.ca
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include <epicsThread.h>
#include <cantProceed.h>

#include <seqCom.h>
#include <ioccrf.h>

/*
 * Until the mechanism for registering sequencer programs and commands
 * has been finalized I've got a couple of different methods supported
 * in this source.  At the moment I'm using C++ constructors to generate
 * the calls, so SEQ_PROG_REG is defined.
 */
#define SEQ_PROG_REG

/*
 * Prototypes (these probably belong in seqCom.h)
 */
long seqShow (epicsThreadId);
long seqChanShow (epicsThreadId, char *);
long seqQueueShow (epicsThreadId tid);
long seqStop (epicsThreadId);

#ifdef SEQ_PROG_REG
struct sequencerProgram {
    struct seqProgram *prog;
    struct sequencerProgram *next;

};
static struct sequencerProgram *seqHead;

/*
 * This routine is called before multitasking has started, so there's
 * no race condition in creating the linked list.
 */
void epicsShareAPI
seqRegisterSequencerProgram (struct seqProgram *p)
{
    struct sequencerProgram *sp;

    sp = (struct sequencerProgram *)mallocMustSucceed (sizeof *sp, "seqRegisterSequencerProgram");
    sp->prog = p;
    sp->next = seqHead;
    seqHead = sp;
}
#endif

/*
 * Find a thread by name or ID number
 */
static epicsThreadId
findThread (const char *name)
{
    epicsThreadId id;
    char *term;

    id = (epicsThreadId)strtoul (name, &term, 16);
    if ((term != name) && (*term == '\0'))
        return id;
    id = epicsThreadGetId (name);
    if (id)
        return id;
    printf ("No such thread.\n");
    return NULL;
}

/* seq */
static const ioccrfArg seqArg0 = { "sequencer",ioccrfArgString};
static const ioccrfArg seqArg1 = { "macro definitions",ioccrfArgString};
static const ioccrfArg seqArg2 = { "stack size",ioccrfArgInt};
static const ioccrfArg * const seqArgs[3] = { &seqArg0,&seqArg1,&seqArg2 };
static const ioccrfFuncDef seqFuncDef = {"seq",3,seqArgs};
static void seqCallFunc(const ioccrfArgBuf *args)
{
    char *table = args[0].sval;
    char *macroDef = args[1].sval;
    int stackSize = args[2].ival;
#ifdef SEQ_PROG_REG
    struct sequencerProgram *sp;
#else
    extern struct seqProgram * const seqPrograms[];
    struct seqProgram * const *spp;
#endif

    if (!table) {
        printf ("No sequencer specified.\n");
        return;
    }
    if (*table == '&')
        table++;
#ifdef SEQ_PROG_REG
    for (sp = seqHead ; sp != NULL ; sp = sp->next) {
        if (!strcmp (table, sp->prog->pProgName)) {
            seq (sp->prog, macroDef, stackSize);
#else
    for (spp = seqPrograms ; *spp != NULL ; spp++) {
        if (!strcmp (table, (*spp)->pProgName)) {
            seq (*spp, macroDef, stackSize);
#endif
            return;
        }
    }
    printf ("Can't find sequencer `%s'.\n", table);
}

/* seqShow */
static const ioccrfArg seqShowArg0 = { "sequencer",ioccrfArgString};
static const ioccrfArg * const seqShowArgs[1] = {&seqShowArg0};
static const ioccrfFuncDef seqShowFuncDef = {"seqShow",1,seqShowArgs};
static void seqShowCallFunc(const ioccrfArgBuf *args)
{
    epicsThreadId id;
    char *name = args[0].sval;

    if (name == NULL)
        seqShow (NULL);
    else if ((id = findThread (name)) != NULL)
        seqShow (id);
}

/* seqQueueShow */
static const ioccrfArg seqQueueShowArg0 = { "sequencer",ioccrfArgString};
static const ioccrfArg * const seqQueueShowArgs[1] = {&seqQueueShowArg0};
static const ioccrfFuncDef seqQueueShowFuncDef = {"seqQueueShow",1,seqQueueShowArgs};
static void seqQueueShowCallFunc(const ioccrfArgBuf *args)
{
    epicsThreadId id;
    char *name = args[0].sval;

    if ((name != NULL) && ((id = findThread (name)) != NULL))
        seqQueueShow (id);
}

/* seqStop */
static const ioccrfArg seqStopArg0 = { "sequencer",ioccrfArgString};
static const ioccrfArg * const seqStopArgs[1] = {&seqStopArg0};
static const ioccrfFuncDef seqStopFuncDef = {"seqStop",1,seqStopArgs};
static void seqStopCallFunc(const ioccrfArgBuf *args)
{
    epicsThreadId id;
    char *name = args[0].sval;

    if ((name != NULL) && ((id = findThread (name)) != NULL))
        seqStop (id);
}

/* seqChanShow */
static const ioccrfArg seqChanShowArg0 = { "sequencer",ioccrfArgString};
static const ioccrfArg seqChanShowArg1 = { "channel",ioccrfArgString};
static const ioccrfArg * const seqChanShowArgs[2] = {&seqChanShowArg0,&seqChanShowArg1};
static const ioccrfFuncDef seqChanShowFuncDef = {"seqChanShow",2,seqChanShowArgs};
static void seqChanShowCallFunc(const ioccrfArgBuf *args)
{
    epicsThreadId id;
    char *name = args[0].sval;
    char *chan = args[1].sval;

    if ((name != NULL) && ((id = findThread (name)) != NULL))
        seqChanShow (id, chan);
}

/*
 * This routine is called before multitasking has started, so there's
 * no race condition in the test/set of firstTime.
 */
void epicsShareAPI
seqRegisterSequencerCommands (void)
{
    static int firstTime = 1;
    if (firstTime) {
        firstTime = 0;
        ioccrfRegister(&seqFuncDef,seqCallFunc);
        ioccrfRegister(&seqShowFuncDef,seqShowCallFunc);
        ioccrfRegister(&seqQueueShowFuncDef,seqQueueShowCallFunc);
        ioccrfRegister(&seqStopFuncDef,seqStopCallFunc);
        ioccrfRegister(&seqChanShowFuncDef,seqChanShowCallFunc);
    }
}