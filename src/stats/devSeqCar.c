/*************************************************************************\
This file is distributed subject to a Software License Agreement found
in the file LICENSE that is included with this distribution.
\*************************************************************************/
/* Device support to permit database access to sequencer internals
 *
 * This is experimental only. Note the following:
 *
 * 1. uses INST_IO (an unstructured string)
 *
 * 2. string is a command:
 *    nPgms
 *    nChans
 *    nConnect
 *    nDisconnect
 * Original Auth:   Richard Dabney, SLAC
 */

#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
#  include <malloc.h>
#elif (__STDC_VERSION__ < 199901L) && !defined(__GNUC__)
#  include <alloca.h>
#endif

#include "alarm.h"
#include "dbDefs.h"
#include "dbAccess.h"
#include "recSup.h"
#include "devSup.h"
#include "link.h"
#include "dbScan.h"
#include "longinRecord.h"
#include "epicsEvent.h"
#include "epicsExport.h"

#include "pv.h"
#include "seqCom.h"
#include "seqPvt.h"
#include "seq_debug.h"

typedef struct {
    long	number;
    DEVSUPFUN	report;
    DEVSUPFUN	init;
    DEVSUPFUN	init_record;
    DEVSUPFUN   get_ioint_info;
    DEVSUPFUN	read_or_write;
    DEVSUPFUN	special_linconv;
} DSET;

static long liInit( struct longinRecord *rec );
static long liRead( struct longinRecord *rec );
static long liGetIoInitInfo(int cmd, struct longinRecord *rec, IOSCANPVT *ppvt);
static DSET  devLiSeqCar = { 5, NULL, NULL, liInit, liGetIoInitInfo, liRead, NULL };
epicsExportAddress(dset,devLiSeqCar);

static void devSeqCarScanThreadSpawn(void *);
static void devSeqCarScanThread(void *);

static epicsThreadOnceId devSeqCarScanThreadOnceFlag = EPICS_THREAD_ONCE_INIT;
static char*             devSeqCarScanThreadName     = "devSeqCarScan";
static ELLLIST           devSeqCarScanList;

/* Commands  */
static char *nPgms          = "nPgms";
static char *nChans         = "nChans";
static char *nConnect       = "nConnect";
static char *nDisconnect    = "nDisconnect";

enum {
    notUpdated = 0,
    updated,
    notFound
};

typedef enum {
    seqCarShownPgms = 0,
    seqCarShownChans,
    seqCarShownConnect,
    seqCarShownDisconnect,
    seqCarShowsyntaxErr
} seqCarShowVarType;

typedef struct {
    unsigned nPgms;
    unsigned nChans;
    unsigned nConnect;
    unsigned nDisconnect;
    char *syntaxErrMsg;
} seqCarShowVar;

typedef struct 
{
    int     level;
    int     nPgms;
    int     nChans;
    int     nConnect;
    int     nDisconnect;
} seqCarStats;

typedef struct {
    ELLNODE               devScanNode;
    IOSCANPVT             ioScanPvt;
    seqCarShowVarType     type;
    char                  progName[80];
    char                  stateSetName[80];
    char                  updateFlag;
    epicsMutexId          mutexId;
    seqCarShowVar         var;
    seqCarStats           statsVar;
} seqCarShowScanPvt;

#define UPDATE_SEQCAR_VAR(UPDATEFLAG, SOURCE, TARGET) \
        if((UPDATEFLAG) || ((TARGET) != (SOURCE))) {\
            (TARGET) = (SOURCE); \
            (UPDATEFLAG) = updated; \
        }

static seqCarShowScanPvt* seqCarShowScanPvtInit(struct link* link)
{
    seqCarShowScanPvt   *pvtPt;
#if (__STDC_VERSION__ >= 199901L) || defined(__GNUC__)
    char             inpStr[strlen(link->value.instio.string)+1];
#else
    char             *inpStr = (char *)alloca(strlen(link->value.instio.string)+1);
#endif

    pvtPt = (seqCarShowScanPvt *) malloc(sizeof(seqCarShowScanPvt));
    if(!pvtPt) 
        return NULL;

    strcpy(inpStr,link->value.instio.string);

    /* see if we have a hit for the command */
    if (!strcmp(inpStr,nPgms))               
        pvtPt->type = seqCarShownPgms;
    else if(!strcmp(inpStr,nChans))         
        pvtPt->type = seqCarShownChans;
    else if(!strcmp(inpStr,nConnect))       
        pvtPt->type = seqCarShownConnect;
    else if(!strcmp(inpStr,nDisconnect))    
        pvtPt->type = seqCarShownDisconnect;
    else 
    {
        free(pvtPt);
        return (NULL);
    }

    pvtPt->updateFlag = updated;
    pvtPt->mutexId = epicsMutexCreate();
    scanIoInit(&pvtPt->ioScanPvt);

    return (pvtPt);
}


static long liInit( struct longinRecord *rec )
{
    struct link      *link   = &rec->inp;

    /* check that link is of type INST_IO */
    if ( link->type != INST_IO ) {
        return S_db_badField;
    }

    rec->dpvt = (void *) seqCarShowScanPvtInit(link);
    if(!rec->dpvt) 
    {
        return S_db_errArg;
    }

    epicsThreadOnce(&devSeqCarScanThreadOnceFlag, (void(*)(void *)) devSeqCarScanThreadSpawn, (void *) rec->dpvt);

    ellAdd(&devSeqCarScanList, &(((seqCarShowScanPvt *) rec->dpvt)->devScanNode));

    return 0;
}

static void devSeqCarScanThreadSpawn(void *dpvt)
{
    epicsUInt32 devSeqCarScanStack;

    /* Spawn the Scan Task */
    devSeqCarScanStack = epicsThreadGetStackSize(epicsThreadStackMedium);
    epicsThreadCreate(devSeqCarScanThreadName, THREAD_PRIORITY, devSeqCarScanStack,
                      (EPICSTHREADFUNC)devSeqCarScanThread,(void *) dpvt);
}



static void devSeqCarScanThread(void * dpvt)
{
    ELLLIST          *pdevSeqCarScanList = &devSeqCarScanList;
    seqCarShowScanPvt   *pvtPt = (seqCarShowScanPvt *) dpvt;
    seqCarShowVar       *varPt;
    void seqcaStats(seqCarStats *);

    while(!pdevSeqCarScanList->count) {
        epicsThreadSleep(0.5);
    }

    while(TRUE) 
    {
        pvtPt = (seqCarShowScanPvt*) ellFirst(pdevSeqCarScanList);

        seqCarStats stats = {0, 0, 0, 0};
        seqcaStats(&stats);

	do
        {
            varPt = &(pvtPt->var);

            epicsMutexLock(pvtPt->mutexId);
            switch(pvtPt->type)
            {
                case seqCarShownPgms:
                    UPDATE_SEQCAR_VAR(pvtPt->updateFlag, stats.nPgms, varPt->nPgms);
                    break;
                case seqCarShownChans:
                    UPDATE_SEQCAR_VAR(pvtPt->updateFlag, stats.nChans, varPt->nChans);
                    break;
                case seqCarShownConnect:
                    UPDATE_SEQCAR_VAR(pvtPt->updateFlag, stats.nConnect, varPt->nConnect);
                    break;
                case seqCarShownDisconnect:
                    stats.nDisconnect = stats.nChans - stats.nConnect;
                    UPDATE_SEQCAR_VAR(pvtPt->updateFlag, stats.nDisconnect, varPt->nDisconnect);
                    break;
                case seqCarShowsyntaxErr:
                    break;
                default:
                    break;
            }
            epicsMutexUnlock(pvtPt->mutexId);

            if(pvtPt->updateFlag) 
            {
                pvtPt->updateFlag = notUpdated;
                scanIoRequest(pvtPt->ioScanPvt);
            }
        } while( (pvtPt = (seqCarShowScanPvt*) ellNext(&pvtPt->devScanNode)) );
        epicsThreadSleep(10.0);
    } 
}
 
static long liRead( struct longinRecord *rec )
{
    seqCarShowScanPvt    *pvtPt = (seqCarShowScanPvt *)rec->dpvt;
    seqCarShowVar        *varPt;

    if(!pvtPt || pvtPt->updateFlag == notFound ) 
    {
        return 0;
    }
    varPt = &(pvtPt->var);

    epicsMutexLock(pvtPt->mutexId);
    switch(pvtPt->type){
        case seqCarShownPgms:          
            rec->val = pvtPt->var.nPgms;     
            break;
        case seqCarShownChans:         
            rec->val = pvtPt->var.nChans;     
            break;
        case seqCarShownConnect:       
            rec->val = pvtPt->var.nConnect;     
            break;
        case seqCarShownDisconnect:     
            rec->val = pvtPt->var.nDisconnect;     
            break;
        case seqCarShowsyntaxErr:     
            break;
    }
    epicsMutexUnlock(pvtPt->mutexId);

    return 0;
}
       
static long liGetIoInitInfo(int cmd, struct longinRecord *rec, IOSCANPVT *ppvt)
{
    seqCarShowScanPvt  *pvtPt = (seqCarShowScanPvt *)rec->dpvt;

    if (!pvtPt)
        return S_db_badField;
    *ppvt = pvtPt->ioScanPvt;

    return 0;
}

