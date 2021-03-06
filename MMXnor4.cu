#include <iostream>
#include <stdio.h>
#include <iomanip>
#include <cuda_runtime.h>
using namespace std;



void MatrixRandBin(float *mat, int rows, int cols) {
    for (int i = 0; i < rows; i++) {
        for (int j = 0; j < cols; j++) {
            if ((float)rand()/RAND_MAX > 0.5) {
                mat[i*cols+j] = 1.0f;
            }else {
                mat[i*cols+j] = -1.0f;
            }

        }
    }
}

void MatrixPrint(float *mat, int rows, int cols) {
    for (int i = 0; i < rows; i++) {
        for (int j = 0; j < cols; j++) {
            cout << setw(2) << mat[i*cols+j] << " ";
        }
        cout << endl;
    }
    cout << endl;
}

void MatrixPrintD(int *mat, int rows, int cols) {
    for (int i = 0; i < rows; i++) {
        for (int j = 0; j < cols; j++) {
            cout << setw(2) << mat[i*cols+j] << " ";
        }
        cout << endl;
    }
    cout << endl;
}


float MatrixCompare(float *a, float *b, int rows, int cols) {
    float err = 0;
    for (int i = 0; i < rows; i++) {
        for (int j = 0; j < cols; j++) {
            err += abs(a[i*cols+j]-b[i*cols+j]);  
        }
    }
    return err;
}

void MatrixMul_host(float *a, int a_rows, int a_cols, float *b, int b_rows, int b_cols, float *c) {
    for (int i = 0; i < a_rows; i++) {
        for (int j = 0; j < b_cols; j++) {
            float t = 0;
            for (int k = 0; k < b_rows; k++) {
                t += a[i*a_cols+k]*b[k*b_cols+j];
            }
            c[i*b_cols+j] = t;
        }
    }
}

//horizontal
__global__ void AMatrix2Bin(float *a, int *a_bin, int pitch_a, int Pitch_a_bin, int a_rows, int MaxBlocks, int BINSIZE) {
    int tix = threadIdx.x;
    int bix = blockIdx.x;
    int bdx = blockDim.x;
    int gdx = gridDim.x;


    int maxThreads = MaxBlocks*a_rows;
    for (int id = bix*bdx+tix; id < maxThreads; id += gdx*bdx) {
        int rid = id/MaxBlocks;
        int cid = id%MaxBlocks;

        int Integer = 0;
        int base = 1;
        for (int i = 0; i < BINSIZE; i++) {
            if (a[rid*pitch_a+(cid+1)*BINSIZE-1-i] == 1.f) {
                Integer += base;
            }
            base = base<<1;
        }

        a_bin[rid*Pitch_a_bin+cid] = Integer;
    }

}
//vetical
__global__ void BMatrix2Bin(float *b, int *b_bin, int pitch_b, int Pitch_b_bin, int b_cols, int MaxBlocks, int BINSIZE) {
    int tix = threadIdx.x;
    int bix = blockIdx.x;
    int bdx = blockDim.x;
    int gdx = gridDim.x;

    int maxThreads = MaxBlocks*b_cols;
    for (int id = bix*bdx+tix; id < maxThreads; id += gdx*bdx) {
        int cid = id/MaxBlocks;
        int rid = id%MaxBlocks;

        int Integer = 0;
        int base = 1;
        for (int i=0; i < BINSIZE; i++) {
            if (b[((rid+1)*BINSIZE-1-i)*pitch_b+cid] == 1.f) {
                Integer += base;
            }
            base = base<<1;
        }

        b_bin[rid*Pitch_b_bin+cid] = Integer;
    }

}

// __device__ unsigned char __popcount_tab_copy[256];//__constant__ is slower than __device__
// __device__ int popcount (int x) {
//   return __popcount_tab_copy[(x >>  0) & 0xff]  
//   + __popcount_tab_copy[(x >>  8) & 0xff]  
//   + __popcount_tab_copy[(x >> 16) & 0xff] 
//   + __popcount_tab_copy[(x >> 24) & 0xff];
// }


//x is cols, y is rows!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
__global__ void MatrixMulXnor(int *a, int *b, float *result, unsigned char *__popcount_tab,
 	int pitch_a, int pitch_b, int pitch_result,
	int RectSize_n, int midBlocks, int BINSIZE, int RealMidSize) {

    int tix = threadIdx.x;
    int tiy = threadIdx.y;
    int bix = blockIdx.x;
    int biy = blockIdx.y;
    int bdx = blockDim.x;
    int bdy = blockDim.y;
    int gdx = gridDim.x;
    int gdy = gridDim.y;
    // printf(" block:(%d, %d) thread:(%d, %d)\n",bix,biy,tix,tiy );
    // printf(" gridDim:(%d, %d) blockDim:(%d, %d)\n",gdx,gdy,bdx,bdy );


    int rest = BINSIZE*RectSize_n*midBlocks-RealMidSize;

    __shared__ unsigned char __popcount_tab_shared[256];
    __shared__ int a_rect_shared[8][16];
    __shared__ int b_rect_shared[16][8];

 	for (int i = tiy*bdx+tix; i < 256; i += bdx*bdy) {
         __popcount_tab_shared[i] = __popcount_tab[i];
    }
    __syncthreads();


    int sum = 0;
    for (int i = 0; i < midBlocks; i++) {
    	for (int j = tix; j < RectSize_n; j += bdx) {
    		a_rect_shared[tiy][j] = a[(biy*bdy+tiy)*pitch_a+i*RectSize_n+j];
    	}
    	for (int j = tiy; j < RectSize_n; j += bdy) {
    		b_rect_shared[j][tix] = b[(i*RectSize_n+j)*pitch_b+bix*bdx+tix];
    	}
    	__syncthreads();


    	int bin = 0;
    	bin = a_rect_shared[tiy][0]^b_rect_shared[0][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][1]^b_rect_shared[1][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][2]^b_rect_shared[2][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][3]^b_rect_shared[3][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][4]^b_rect_shared[4][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][5]^b_rect_shared[5][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][6]^b_rect_shared[6][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][7]^b_rect_shared[7][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][8]^b_rect_shared[8][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][9]^b_rect_shared[9][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][10]^b_rect_shared[10][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][11]^b_rect_shared[11][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][12]^b_rect_shared[12][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][13]^b_rect_shared[13][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][14]^b_rect_shared[14][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    bin = a_rect_shared[tiy][15]^b_rect_shared[15][tix];
	    sum += BINSIZE-2*(	__popcount_tab_shared[(bin >>  0) & 0xff]  
						  + __popcount_tab_shared[(bin >>  8) & 0xff]  
						  + __popcount_tab_shared[(bin >> 16) & 0xff] 
						  + __popcount_tab_shared[(bin >> 24) & 0xff]);

	    __syncthreads();
    }
    result[(biy*bdy+tiy)*pitch_result+bix*bdx+tix] = sum-rest;



    // num=0;
    // int rest=(BINSIZE*a_cols-RealMidSize);
    // for(int i=bix;i<a_rows;i+=gdx){
    //     for(int j=tix;j<b_cols;j+=bdx){
    //         // printf("i=%d ; j=%d\n",i,j);
    //         int sum=0;
    //         for(int k=0;k<a_cols;k++){
    //             int bin=(a_shared[num*a_cols+k]^b[k*pitch_b+j]);
    //             int negnum=popcount(bin);
    //             int posnum=BINSIZE-negnum;
    //             //calculate ignores the rest of BINSIZE if the Matsize can't devided by BINSIZE ,it can cause err
    //             //(10/00)'(01/00) should be 0000 but it is 0011,so 1+1 is trash in the result.and it mislead a_rows*b_cols times. 
    //             sum+=(posnum-negnum);
    //         }
    //         result[i*pitch_result+j]=sum-rest;
    //     }
    //     num++;
    // }


}


void MatrixMul_device(float *a, float *b, int a_rows, int a_cols, int b_cols, float *result) {

    int BINSIZE = 32;//size of bin2int, 32 means 0000 0000 0000 0000 0000 0000 0000 0000
    int MaxBlocks = (a_cols-1)/BINSIZE+1;
    int Copysize = MaxBlocks*BINSIZE;
    
    float *a_copy;//a_rows * Copysize
    float *b_copy;//Copysize * b_cols
    size_t Pitch_a_copy, Pitch_b_copy;
    cudaMallocPitch((void**)&a_copy, &Pitch_a_copy, sizeof(float)*Copysize, a_rows);
    cudaMallocPitch((void**)&b_copy, &Pitch_b_copy, sizeof(float)*b_cols, Copysize);
    cudaMemset(a_copy, 0, Pitch_a_copy*a_rows);
    cudaMemset(b_copy, 0, Pitch_b_copy*Copysize);
    cudaMemcpy2D(a_copy, Pitch_a_copy, a, sizeof(float)*a_cols, sizeof(float)*a_cols, a_rows, cudaMemcpyDeviceToDevice);
    cudaMemcpy2D(b_copy, Pitch_b_copy, b, sizeof(float)*b_cols, sizeof(float)*b_cols, a_cols, cudaMemcpyDeviceToDevice);

//check oringin
    // float *a_host;
    // float *b_host;
    // a_host = (float*) malloc(sizeof(float) * Copysize * a_rows);
    // b_host = (float*) malloc(sizeof(float) * b_cols * Copysize);
    // cudaMemcpy2D(a_host,sizeof(float) *Copysize, a_copy,Pitch_a_copy,sizeof(float) *Copysize , a_rows,cudaMemcpyDeviceToHost);
    // cudaMemcpy2D(b_host,sizeof(float) *b_cols, b_copy,Pitch_b_copy,sizeof(float) *b_cols , Copysize,cudaMemcpyDeviceToHost);
    // MatrixPrint(a_host,a_rows,Copysize);
    // MatrixPrint(b_host,Copysize,b_cols);

    //rect[8][16]*[16][32]
	int RectSize_x = 8;
	int RectSize_n = 16;
    int RectSize_y = 8;
    dim3 RectBlockNum_a_bin((MaxBlocks-1)/RectSize_n+1, (a_rows-1)/RectSize_y+1, 1);//with block multiply
    dim3 RectBlockNum_b_bin((b_cols-1)/RectSize_x+1, (MaxBlocks-1)/RectSize_n+1, 1);
    int *a_bin;
    int *b_bin;
    size_t Pitch_a_bin, Pitch_b_bin;
    cudaMallocPitch((void**)&a_bin , &Pitch_a_bin , sizeof(int)*RectSize_n*RectBlockNum_a_bin.x, RectSize_y*RectBlockNum_a_bin.y);
    cudaMallocPitch((void**)&b_bin , &Pitch_b_bin , sizeof(int)*RectSize_x*RectBlockNum_b_bin.x, RectSize_n*RectBlockNum_b_bin.y);
    cudaMemset(a_bin, 0, Pitch_a_bin*RectSize_y*RectBlockNum_a_bin.y);
    cudaMemset(b_bin, 0, Pitch_b_bin*RectSize_n*RectBlockNum_b_bin.y);
    dim3 BS_BIN(512,1,1);
    dim3 GS_BIN(6,1,1);
    AMatrix2Bin<<< GS_BIN, BS_BIN >>>(a_copy, a_bin, 
        Pitch_a_copy/sizeof(float), Pitch_a_bin/sizeof(int), a_rows, MaxBlocks, BINSIZE);
    BMatrix2Bin<<< GS_BIN, BS_BIN >>>(b_copy, b_bin, 
        Pitch_b_copy/sizeof(float), Pitch_b_bin/sizeof(int), b_cols, MaxBlocks, BINSIZE);
    cudaFree(a_copy);
    cudaFree(b_copy);
//check bin
    // int *a_host_bin;
    // int *b_host_bin;
    // a_host_bin = (int*) malloc(sizeof(int) *MaxBlocks * a_rows);
    // b_host_bin = (int*) malloc(sizeof(int) *b_cols * MaxBlocks);
    // cudaMemcpy2D(a_host_bin,sizeof(int) *MaxBlocks, a_bin,Pitch_a_bin,sizeof(int) *MaxBlocks , a_rows ,cudaMemcpyDeviceToHost);
    // cudaMemcpy2D(b_host_bin,sizeof(int) *b_cols, b_bin,Pitch_b_bin,sizeof(int) *b_cols , MaxBlocks ,cudaMemcpyDeviceToHost);
    // MatrixPrintD(a_host_bin,a_rows,MaxBlocks);
    // MatrixPrintD(b_host_bin,MaxBlocks,b_cols);


    float *result_bin;//a_rows * b_cols
    size_t Pitch_result_bin;
    cudaMallocPitch((void**)&result_bin , &Pitch_result_bin , sizeof(float)*RectSize_x*RectBlockNum_b_bin.x, RectSize_y*RectBlockNum_a_bin.y);

    const unsigned char __popcount_tab[] = {
      0,1,1,2,1,2,2,3,1,2,2,3,2,3,3,4,1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,
      1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
      1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
      2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
      1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
      2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
      2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
      3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,4,5,5,6,5,6,6,7,5,6,6,7,6,7,7,8,
    };
    unsigned char *__popcount_tab_copy;
    cudaMalloc((void**)&__popcount_tab_copy, sizeof(__popcount_tab));
    cudaMemcpy(__popcount_tab_copy, __popcount_tab, sizeof(__popcount_tab), cudaMemcpyHostToDevice);

    cudaEvent_t start_device, stop_device;
    float time_device;
    cudaEventCreate(&start_device);
    cudaEventCreate(&stop_device);
    cudaEventRecord(start_device, 0);

    dim3 BS_MM(RectSize_x, RectSize_y, 1);
    dim3 GS_MM(RectBlockNum_b_bin.x, RectBlockNum_a_bin.y, 1);
    MatrixMulXnor<<< GS_MM, BS_MM >>>(a_bin, b_bin, result_bin, __popcount_tab_copy,
     	Pitch_a_bin/sizeof(int), Pitch_b_bin/sizeof(int), Pitch_result_bin/sizeof(float),
     	RectSize_n, RectBlockNum_a_bin.x, BINSIZE, a_cols);

    cudaEventRecord( stop_device, 0 );
    cudaEventSynchronize( stop_device );
    cudaEventElapsedTime( &time_device, start_device, stop_device );
    cudaEventDestroy( start_device );
    cudaEventDestroy( stop_device );
    cout<<"gputime="<<time_device<<"ms"<<endl;

    cudaMemcpy2D(result,sizeof(float) *b_cols, result_bin,Pitch_result_bin,sizeof(float) *b_cols , a_rows ,cudaMemcpyDeviceToDevice);

    cudaFree(a_bin);
    cudaFree(b_bin);
    cudaFree(result_bin);
}

int main(){

//simulate pytorch param
    int x = 2000;
    int n = 2000;
    int y = 2000;
    float *a_host;
    float *b_host;
    float *result_host;
    a_host = (float*) malloc(sizeof(float) * x * n);
    b_host = (float*) malloc(sizeof(float) * n * y);
    result_host = (float*) malloc(sizeof(float) * x * y);
    srand(0);
    MatrixRandBin(a_host,x,n);
    MatrixRandBin(b_host,n,y);
    // cout<<MatrixCopysize<<endl;

    float *a_copy;
    float *b_copy;
    float *result_device;
    cudaMalloc((void**)&a_copy,sizeof(float) *x * n);
    cudaMalloc((void**)&b_copy,sizeof(float) *n * y);
    cudaMalloc((void**)&result_device,sizeof(float) *x * y);
    cudaMemcpy(a_copy,a_host,sizeof(float) *x * n,cudaMemcpyHostToDevice);
    cudaMemcpy(b_copy,b_host,sizeof(float) *n * y,cudaMemcpyHostToDevice);


    // MatrixPrint(a_host,x,n);
    // MatrixPrint(b_host,n,y);

//run in gpu warp in C code
    MatrixMul_device(a_copy,b_copy,x,n,y,result_device);

    cudaMemcpy(result_host, result_device,sizeof(float) *x * y,cudaMemcpyDeviceToHost);
    cudaFree(a_copy);
    cudaFree(b_copy);
    cudaFree(result_device);
    // MatrixPrint(result_host,x,y);

// //run in cpu
//     float *result_cpu;
//     result_cpu = (float*) malloc(sizeof(float) * x * y);
//     clock_t start_host = clock();
//     MatrixMul_host(a_host,x,n,b_host,n,y,result_cpu);
//     cout<<"cputime="<<(double)(clock() - start_host)/1000<<"ms"<<endl;
//     // MatrixPrint(result_cpu,x,y);


// //compare value of gpu and cpu
//     float err=MatrixCompare(result_cpu,result_host,x,y);
//     cout<<"err in gpu and cpu = "<<err<<endl;

    return 0;
}