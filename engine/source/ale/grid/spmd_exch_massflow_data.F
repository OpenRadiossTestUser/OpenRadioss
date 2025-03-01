Copyright>        OpenRadioss
Copyright>        Copyright (C) 1986-2023 Altair Engineering Inc.
Copyright>
Copyright>        This program is free software: you can redistribute it and/or modify
Copyright>        it under the terms of the GNU Affero General Public License as published by
Copyright>        the Free Software Foundation, either version 3 of the License, or
Copyright>        (at your option) any later version.
Copyright>
Copyright>        This program is distributed in the hope that it will be useful,
Copyright>        but WITHOUT ANY WARRANTY; without even the implied warranty of
Copyright>        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
Copyright>        GNU Affero General Public License for more details.
Copyright>
Copyright>        You should have received a copy of the GNU Affero General Public License
Copyright>        along with this program.  If not, see <https://www.gnu.org/licenses/>.
Copyright>
Copyright>
Copyright>        Commercial Alternative: Altair Radioss Software
Copyright>
Copyright>        As an alternative to this open-source version, Altair also offers Altair Radioss
Copyright>        software under a commercial license.  Contact Altair to discuss further if the
Copyright>        commercial version may interest you: https://www.altair.com/radioss/.
Chd|====================================================================
Chd|  SPMD_EXCH_MASSFLOW_DATA       source/ale/grid/spmd_exch_massflow_data.F
Chd|-- called by -----------
Chd|        ALEW7                         source/ale/grid/alew7.F       
Chd|-- calls ---------------
Chd|        ALE_MOD                       ../common_source/modules/ale/ale_mod.F
Chd|====================================================================
      SUBROUTINE SPMD_EXCH_MASSFLOW_DATA( DOMAIN_DATA, NSPMD  )
C-----------------------------------------------
C   M o d u l e s
C-----------------------------------------------
      USE ALE_MOD
C-----------------------------------------------
C   D e s c r i p t i o n
C-----------------------------------------------
C SPMD exchange necessary for option /ALE/GRID/MASSFLOW
C
C  gathering  SUM(mi.eps,i) : DOMAIN_DATA%EP(1:9)
C  gathering  SUM(mi)       : DOMAIN_DATA%SUM_M
C  then averaging eps tensor (L)
C  deducde spherical tensor %LD and anti-symmetrical tensor %LW  (L=DL+LW)
C when finished, reset DOMAIN_DATA%SUM_M
!           DOMAIN_DATA%EP(1:9) = DOMAIN_DATA%EP(1:9) / DOMAIN_DATA%SUM_M
!           DOMAIN_DATA%SUM_M = ZERO !used for elem mass in sforc3, used below for nodal mass
!           DOMAIN_DATA%LD(1) = ...
!           DOMAIN_DATA%LW(3) = ...
C-----------------------------------------------
C   I m p l i c i t   T y p e s
C-----------------------------------------------
#include      "implicit_f.inc"
C-----------------------------------------------
C   M e s s a g e   P a s s i n g
C-----------------------------------------------
#ifdef MPI
#include "mpif.h"
#endif
C-----------------------------------------------
C   C o m m o n   B l o c k s
C-----------------------------------------------
#include      "task_c.inc"
C-----------------------------------------------
C   D u m m y   A r g u m e n t s
C-----------------------------------------------
      TYPE(MASSFLOW_DATA_),INTENT(INOUT)::DOMAIN_DATA
      INTEGER,INTENT(IN)::NSPMD
C-----------------------------------------------
C   L o c a l   V a r i a b l e s
C-----------------------------------------------
#ifdef MPI
      INTEGER I, LENCOM
      INTEGER IERROR, MSGTYP, MSGOFF, NBIRECV, P
      INTEGER ::  STATUS(MPI_STATUS_SIZE),REQ_SB(NSPMD),
     .            REQ_RB(NSPMD),IRINDEXI(NSPMD),
     .            REQ_RD(NSPMD),REQ_SD(NSPMD),REQ_SD2(NSPMD),
     .            REQ_RC(NSPMD),REQ_SC(NSPMD),
     .            ISINDEXI(NSPMD)
      INTEGER :: LOC_PROC, ISIZE
      my_real :: RBUF(10,NSPMD)
      DATA MSGOFF/2205/
C-----------------------------------------------
C   P r e c o n d i t i o n
C-----------------------------------------------
      IF(NSPMD == 1)RETURN
C-----------------------------------------------
C   S o u r c e   L i n e s
C-----------------------------------------------
!$OMP SINGLE
        LOC_PROC=ISPMD+1
        RBUF(1:10,1:NSPMD) = ZERO
        RBUF(1:9,LOC_PROC) = DOMAIN_DATA%EP(1:9) !sum(mass*epsilon)
        RBUF(10,LOC_PROC) = DOMAIN_DATA%SUM_M    !sum(mass)
        ISIZE=10
        !-------------------------------------------!
        ! SENDING %EP(1:9)                          !
        !-------------------------------------------!
        DO P = 1, NSPMD
          IF(P /= LOC_PROC) THEN
            MSGTYP = MSGOFF
            CALL MPI_ISEND(RBUF(1,LOC_PROC),ISIZE,REAL,IT_SPMD(P),MSGTYP,MPI_COMM_WORLD,REQ_SB(P),IERROR)
          ENDIF
        ENDDO
        !-------------------------------------------!
        ! RECIEVING %EP(1:9)                        !
        !-------------------------------------------!
        NBIRECV=0
        DO P = 1, NSPMD
          IF(LOC_PROC/=P) THEN
            NBIRECV=NBIRECV+1
            IRINDEXI(NBIRECV)=P
            MSGTYP = MSGOFF
            CALL MPI_RECV(RBUF(1,P), ISIZE, REAL, IT_SPMD(P), MSGTYP, MPI_COMM_WORLD, STATUS, IERROR)
          ENDIF
        ENDDO
        !-------------------------------------------!
        !     MPI_WAITING                           !
        !-------------------------------------------!
        DO P = 1, NSPMD
          IF(P/=LOC_PROC) THEN
            CALL MPI_WAIT(REQ_SB(P),STATUS,IERROR)
          ENDIF
        ENDDO

        !-------------------------------------------!
        ! COMPUTE AVERAGE ON CurRENT DOMAIN         !
        !-------------------------------------------!
        DOMAIN_DATA%EP(1:9)=ZERO
        DOMAIN_DATA%SUM_M=ZERO

        DO P=1,NSPMD
          DOMAIN_DATA%EP(1) = DOMAIN_DATA%EP(1) + RBUF(1,P)
          DOMAIN_DATA%EP(2) = DOMAIN_DATA%EP(2) + RBUF(2,P)
          DOMAIN_DATA%EP(3) = DOMAIN_DATA%EP(3) + RBUF(3,P)
          DOMAIN_DATA%EP(4) = DOMAIN_DATA%EP(4) + RBUF(4,P)
          DOMAIN_DATA%EP(5) = DOMAIN_DATA%EP(5) + RBUF(5,P)
          DOMAIN_DATA%EP(6) = DOMAIN_DATA%EP(6) + RBUF(6,P)
          DOMAIN_DATA%EP(7) = DOMAIN_DATA%EP(7) + RBUF(7,P)
          DOMAIN_DATA%EP(8) = DOMAIN_DATA%EP(8) + RBUF(8,P)
          DOMAIN_DATA%EP(9) = DOMAIN_DATA%EP(9) + RBUF(9,P)
          DOMAIN_DATA%SUM_M = DOMAIN_DATA%SUM_M + RBUF(10,P)
        ENDDO

        !CALL FLUSH(6)
        !CALL SPMD_BARRIER()

!$OMP END SINGLE
C-----------------------------------------------
#endif
        RETURN
      END SUBROUTINE