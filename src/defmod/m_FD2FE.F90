module FD2FE 

#include <petscversion.h>

  use global
  implicit none
#include "petscdef.h"

! ------------------FD variables needed by FE------------------------------
! total number of grid points in each direction of the grid
  integer :: nx,ny,nz
  integer :: nprc_x,nprc_y ! horizontal division of FD domain 
  integer :: nprc_fd
  integer :: nxp,nyp ! number of layers in one dim
! size of a grid cell
  real(8) :: dx,dy,dz
! FD domain origin in FE coordination (SCEC205)
  real(8) :: xref,yref,zref
 
contains

  ! Initiate FD model
  subroutine FDInit
    implicit none
    character(256) :: name,name0,name1
    name0=output_file(:index(output_file,"/",BACK=.TRUE.))
    name1=output_file(index(output_file,"/",BACK=.TRUE.)+1:)
    write(name,'(A,A,A)')trim(name0),trim(name1),"_fe.cfg"
    open(149,file=adjustl(name),status='old')
    select case(dmn)
    case(2)
        read(149,*)nprc_x
        read(149,*)nx,ny
        read(149,*)xref,yref
    case(3)
        read(149,*)nprc_x,nprc_y
        read(149,*)nx,ny,nz
        read(149,*)dx,dy,dz
        read(149,*)xref,yref,zref
    end select
    nxp=nx/nprc_x; nyp=ny/nprc_y
    nprc_fd=nprc_x*nprc_y 
    close(149)
  end subroutine FDInit

  ! FD domain grid blocks containing fault nodes (idgp, xgp) 
  subroutine GetFDFnd
    implicit none
    integer :: j2,j3,xid,yid,zid,rowfd(2**dmn),iddf(nfnd*(2**dmn),dmn),uniq(nfnd*(2**dmn))
    real(8) :: x0,x1,y0,y1,z0,z1,xfe(nfnd*(2**dmn),dmn)
    do j3=1,nfnd
       rowfd=(/((j3-1)*(2**dmn)+j2,j2=1,2**dmn)/)
       uniq(rowfd)=rowfd
       select case(dmn)
       case(2)
          xid=int( (xfnd(j3,1)*km2m-xref)/dx)+1
          yid=int(-(xfnd(j3,2)*km2m-yref)/dy)+1
          iddf(rowfd(1),:)=(/xid  ,yid  /)
          iddf(rowfd(2),:)=(/xid+1,yid  /)
          iddf(rowfd(3),:)=(/xid  ,yid+1/)
          iddf(rowfd(4),:)=(/xid+1,yid+1/)
          x1=dble(xid)*dx+xref; y1=-dble(yid)*dy+yref
          x0=x1-dx; y0=y1-dy
          xfe(rowfd(1),:)=(/x0,y0/)
          xfe(rowfd(2),:)=(/x1,y0/)
          xfe(rowfd(3),:)=(/x0,y1/)
          xfe(rowfd(4),:)=(/x1,y1/)
       case(3)
          xid=int( (xfnd(j3,1)*km2m-xref)/dx)+1
          yid=int( (xfnd(j3,2)*km2m-yref)/dy)+1
          zid=int(-(xfnd(j3,3)*km2m-zref)/dz)+1 ! deep positive in swpc
          ! FD node index of the containing block
          iddf(rowfd(1),:)=(/xid  ,yid  ,zid  /)
          iddf(rowfd(2),:)=(/xid+1,yid  ,zid  /)
          iddf(rowfd(3),:)=(/xid  ,yid+1,zid  /)
          iddf(rowfd(4),:)=(/xid  ,yid  ,zid+1/)
          iddf(rowfd(5),:)=(/xid+1,yid+1,zid  /)
          iddf(rowfd(6),:)=(/xid+1,yid  ,zid+1/)
          iddf(rowfd(7),:)=(/xid  ,yid+1,zid+1/)
          iddf(rowfd(8),:)=(/xid+1,yid+1,zid+1/)
          x1=dble(xid)*dx+xref; y1=dble(yid)*dy+yref; z1=-dble(zid)*dz+zref
          x0=x1-dx; y0=y1-dy; z0=z1+dz ! deep positive in swpc
          xfe(rowfd(1),:)=(/x0,y0,z0/)
          xfe(rowfd(2),:)=(/x1,y0,z0/)
          xfe(rowfd(3),:)=(/x0,y1,z0/)
          xfe(rowfd(4),:)=(/x0,y0,z1/)
          xfe(rowfd(5),:)=(/x1,y1,z0/)
          xfe(rowfd(6),:)=(/x1,y0,z1/)
          xfe(rowfd(7),:)=(/x0,y1,z1/)
          xfe(rowfd(8),:)=(/x1,y1,z1/)
       end select
       ! Create a unique index set
       call GetUniq(iddf(:rowfd(2**dmn),:),rowfd(2**dmn),uniq(rowfd(2**dmn)-2**dmn+1:rowfd(2**dmn)))
    end do ! Local fault nodes
    ngp=size(pack(uniq,uniq/=0))
    allocate(idgp(ngp,dmn),xgp(ngp,dmn))
    idgp=iddf(pack(uniq,uniq/=0),:)
    xgp=xfe(pack(uniq,uniq/=0),:)
  end subroutine GetFDFnd

  ! Find if the idset content is unique
  subroutine GetUniq(idset,nrow,uniq)
    implicit none
    integer :: i,j,nrow,idset(nrow,dmn),uniq(2**dmn),ids(2**dmn,dmn)
    ids=idset(nrow-2**dmn+1:,:)
    do i=1,2**dmn
       do j=nrow-2**dmn,1,-1
          if (all((idset(j,:)-ids(i,:))==0)) then 
             uniq(i)=0
             exit 
          end if
       end do
    end do
  end subroutine GetUniq

  ! Extract FD grid velocity, only for dynamic
  subroutine GetVec_fd
    implicit none
    integer :: igp,i,j,ind(npel)
    integer,allocatable :: row(:)
    real(8) :: vecshp(npel,1)
    real(8),allocatable :: vectmp(:,:),mattmp(:,:)
    allocate(row(dmn*npel),vectmp(dmn,1),mattmp(dmn,npel))
    do igp=1,ngp_loc
       ind=gpnlst(igp,:)
       do i=1,npel
          row((/((i-1)*dmn+j,j=1,dmn)/))=(/((ind(i)-1)*dmn+j,j=1,dmn)/)
       end do
       mattmp=reshape(uu_dyn(row),(/dmn,npel/))
       vecshp=reshape(gpshape(igp,:),(/npel,1/))
       vectmp=matmul(mattmp,vecshp)
       uu_fd(igp,:)=vectmp(:,1)/dt_dyn
    end do
  end subroutine GetVec_fd

  ! FE to FD MPI rank match (depending on FD partitioning) 
  subroutine NndFE2FD 
    implicit none
#include "petsc.h"
    integer :: rankfd,rankxy,igp,i,j,k,hit(ngp_loc),buf(nprcs*nprc_fd),nnd_fe2fd(nprcs,nprc_fd),nnd_loc(nprc_fd)
    character(256) :: name,name0,name1
    ! Find index size for local FD ranks
    do rankfd=0,nprc_fd-1
       hit=0
       do igp=1,ngp_loc
          i=idgp_loc(igp,1) 
          j=idgp_loc(igp,2)
          rankxy=((j-1)/nyp)*nprc_x+(i-1)/nxp
          if (rankxy==rankfd) hit(igp)=1
       end do
       nnd_loc(rankfd+1)=sum(hit)
    end do
    call MPI_Gather(nnd_loc,nprc_fd,MPI_Integer,buf,nprc_fd,MPI_Integer,nprcs-1,MPI_Comm_World,ierr)
    if (rank==nprcs-1) then 
       nnd_fe2fd=transpose(reshape(buf,(/nprc_fd,nprcs/)))
       name0=output_file(:index(output_file,"/",BACK=.TRUE.))
       name1=output_file(index(output_file,"/",BACK=.TRUE.)+1:)
       write(name,'(A,A,A)')trim(name0),trim(name1),"_fe2fd.txt"
       open(150,file=adjustl(name),status='replace')
       write(150,*)nprcs,nprc_fd 
       do k=1,nprcs
          write(150,*)nnd_fe2fd(k,:)
       end do
       close(150)
    end if
  end subroutine NndFE2FD 

  ! Mat type from FE to FD (matFD(idx0,idx1,idy0,idy1,idz0,idz1,idmat))
  subroutine MatFE2FD
     implicit none
#include "petsc.h"
     integer :: k,el,matFD(nels,dmn*2+1),hasFD(nprc_fd),ixmin,iymin,izmin,ixmax,iymax,izmax, &
        rankx,rankx0,rankx1,ranky,ranky0,ranky1,rankxy,buf(nprcs*nprc_fd),vfe2fd(nprcs,nprc_fd)
     real(8) :: xmin,ymin,zmin,xmax,ymax,zmax
     character(256) :: name,name0,name1,namev
     select case(dmn)
     case(2)
        xmin=minval(coords(:,1)); xmax=maxval(coords(:,1))
        ymin=minval(coords(:,2)); ymax=maxval(coords(:,2))
        ixmin=int(( xmin-xref)/dx)+1; ixmax=int(( xmax-xref)/dx)+1
        iymin=int((-ymin+yref)/dy)+1; iymax=int((-ymax+yref)/dy)+1
        do el=1,nels 
           enodes=nodes(el,:)
           ecoords=coords(enodes,:)
           xmin=minval(ecoords(:,1)); xmax=maxval(ecoords(:,1))
           ymin=minval(ecoords(:,2)); ymax=maxval(ecoords(:,2))
           ixmin=int(( xmin-xref)/dx)+1; ixmax=int(( xmax-xref)/dx)+1
           iymin=int((-ymin+yref)/dy)+1; iymax=int((-ymax+yref)/dy)+1
           matFD(el,:)=(/ixmin,ixmax,iymin,iymax,id(el)/)
        end do
     case(3)
        xmin=minval(coords(:,1)); xmax=maxval(coords(:,1))
        ymin=minval(coords(:,2)); ymax=maxval(coords(:,2))
        ixmin=int((xmin-xref)/dx)+1; ixmax=int((xmax-xref)/dx)+1
        iymin=int((ymin-yref)/dy)+1; iymax=int((ymax-yref)/dy)+1
        rankx0=(ixmin-1)/nxp
        rankx1=(ixmax-1)/nxp
        ranky0=(iymin-1)/nyp
        ranky1=(iymax-1)/nyp
        hasFD=0
        do rankx=0,nprc_x-1
           do ranky=0,nprc_y-1
              rankxy=ranky*nprc_x+rankx
              if (rankx>=rankx0 .and. & 
                  rankx<=rankx1 .and. &
                  ranky>=ranky0 .and. &
                  ranky<=ranky1) hasFD(rankxy+1)=1
           end do
        end do
        call MPI_Gather(hasFD,nprc_fd,MPI_Integer,buf,nprc_fd,MPI_Integer,nprcs-1,MPI_Comm_World,ierr) 
        name0=output_file(:index(output_file,"/",BACK=.TRUE.))
        name1=output_file(index(output_file,"/",BACK=.TRUE.)+1:)
        if (rank==nprcs-1) then 
           vfe2fd=transpose(reshape(buf,(/nprc_fd,nprcs/)))
           write(name,'(A,A,A)')trim(name0),trim(name1),"_mfe2fd.txt"
           open(151,file=adjustl(name),status='replace')
           write(151,*)size(mat(:,1)),size(mat(1,:)),nprcs,nprc_fd
           do k=1,size(mat(:,1))
              write(151,*)mat(k,:)
           end do
           do k=1,nprcs
              write(151,*)vfe2fd(k,:)
           end do
           close(151)
        end if
        do el=1,nels 
           enodes=nodes(el,:)
           ecoords=coords(enodes,:)
           xmin=minval(ecoords(:,1)); xmax=maxval(ecoords(:,1))
           ymin=minval(ecoords(:,2)); ymax=maxval(ecoords(:,2))
           zmin=minval(ecoords(:,3)); zmax=maxval(ecoords(:,3))
           ixmin=int(( xmin-xref)/dx)+1; ixmax=int(( xmax-xref)/dx)+1
           iymin=int(( ymin-yref)/dy)+1; iymax=int(( ymax-yref)/dy)+1
           izmin=int((-zmax+zref)/dz)+1; izmax=int((-zmin+zref)/dz)+1
           matFD(el,:)=(/ixmin,ixmax,iymin,iymax,izmin,izmax,id(el)/)
        end do
        write(namev,'(A,A,A,I0.6,A)')trim(name0),trim(name1),"_",rank,"_ife2fd.txt"
        open(152,file=adjustl(namev),status='replace')
        write(152,'(I0)')nels
        do el=1,nels
           write(152,'(7(I0,X))')matFD(el,:) 
        end do
        close(152)
     end select
  end subroutine MatFE2FD

  subroutine WriteOutput_fd
    implicit none
    integer :: i
    real(8) :: vec(dmn)
    character(64) :: fmt
    character(256) :: name,name0,name1
    integer,save :: k=0
    name0=output_file(:index(output_file,"/",BACK=.TRUE.))
    name1=output_file(index(output_file,"/",BACK=.TRUE.)+1:)
    write(name,'(A,A,A,I0.6,A)')trim(name0),trim(name1),"_",rank,"_fd.txt"
    if (k==0) then
       open(10,file=adjustl(name),status='replace')
       select case(dmn)
       case(2); fmt="(2(I0,1X))"
       case(3); fmt="(3(I0,1X))"
       end select
       write(10,"(I0)")ngp_loc
       do i=1,ngp_loc
          write(10,fmt)idgp_loc(i,:)
       end do
    else
       open(10,file=adjustl(name),status='old',position='append',action='write')
    end if
    select case(dmn)
       case(2); fmt="(2(F0.6,1X))"
       case(3); fmt="(3(F0.6,1X))"
    end select
    do i=1,ngp_loc
       vec=(/uu_fd(i,1),uu_fd(i,2),-uu_fd(i,3)/) ! deep positive in swpc
       write(10,fmt)vec
    end do
    close(10) 
    k=k+1
  end subroutine WriteOutput_fd

end module FD2FE 
