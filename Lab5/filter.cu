// Lab 5, image filters with CUDA.

// Compile with a command-line similar to Lab 4:
// nvcc filter.cu -c -o filter.o
// g++ filter.o milli.c readppm.c -lGL -lm -lcuda -lcudart -L/usr/local/cuda/lib -lglut -arch=sm_30 -o filter

// 2017-11-27: Early pre-release, dubbed "beta".
// 2017-12-03: First official version! Brand new lab 5 based on the old lab 6.
// Better variable names, better prepared for some lab tasks. More changes may come
// but I call this version 1.0b2.
// 2017-12-04: Two fixes: Added command-lines (above), fixed a bug in computeImages
// that allocated too much memory. b3
// 2017-12-04: More fixes: Tightened up the kernel with edge clamping.
// Less code, nicer result (no borders). Cleaned up some messed up X and Y. b4


// Compile:
// g++ -c readppm.c milli.c
// nvcc -c filter.cu
// g++ filter.o readppm.o milli.o -lGL -lglut -L/usr/local/cuda/lib64 -lcudart
// ./a.out

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#ifdef __APPLE__
  #include <GLUT/glut.h>
  #include <OpenGL/gl.h>
#else
  #include <GL/glut.h>
#endif
#include "readppm.h"
#include "milli.h"

// Use these for setting shared memory size.
#define maxKernelSizeX 20
#define maxKernelSizeY 20

#define SUB_SIZE 12
#define FILTER_RAD 4


__global__ void filter(unsigned char *image, unsigned char *out, const unsigned int imagesizey, const unsigned int imagesizex, const int kernelsizex, const int kernelsizey)
{

  // map from blockIdx to pixel position
	int x = blockIdx.x * blockDim.x + threadIdx.x - kernelsizex * (blockIdx.x+4);
	int y = blockIdx.y * blockDim.y + threadIdx.y - kernelsizey * (blockIdx.y+4);

  y = min(max(y, 0), imagesizey-1);
  x = min(max(x, 0), imagesizex-1);

  unsigned const int SHARED_SIZE = (2*maxKernelSizeX+1)*(2*maxKernelSizeY+1);
  const int sharedIndx = threadIdx.x + threadIdx.y * blockDim.x;

  __shared__ int cacheShared[SHARED_SIZE];

  cacheShared[sharedIndx * 3 + 0] = image[(y*imagesizex + x)*3 + 0];
  cacheShared[sharedIndx * 3 + 1] = image[(y*imagesizex + x)*3 + 1];
  cacheShared[sharedIndx * 3 + 2] = image[(y*imagesizex + x)*3 + 2];
  __syncthreads();

  unsigned int divby = (2*kernelsizex+1)*(2*kernelsizey+1);

  unsigned int sumx, sumy, sumz;
  int localY = threadIdx.y;
  int localX = threadIdx.x;

  sumx=0;sumy=0;sumz=0;
  if (localX < blockDim.x + kernelsizex && localY < blockDim.y + kernelsizey &&
      localX > kernelsizex && localY > kernelsizey){ // If inside kernel

    for(int dy=-kernelsizey;dy<=kernelsizey;dy++){
  		for(int dx=-kernelsizex;dx<=kernelsizex;dx++){

        int yy = localY + dy;
        int xx = localX + dx;
        //int yy = min(max(localY+dy, 0), blockDim.y-1);
  			//int xx = min(max(localX+dx, 0), blockDim.x-1);

        int pixIndex = (yy)*blockDim.x+(xx);

  			sumx += cacheShared[(pixIndex)*3+0];
  			sumy += cacheShared[(pixIndex)*3+1];
  			sumz += cacheShared[(pixIndex)*3+2];
      }
    }

    out[(y*imagesizex+x)*3+0] = sumx/divby;
  	out[(y*imagesizex+x)*3+1] = sumy/divby;
  	out[(y*imagesizex+x)*3+2] = sumz/divby;
  }


  /*
  // Original
  int divby = (2*kernelsizex+1)*(2*kernelsizey+1); // Works for box filters only!
  int dy, dx;

  unsigned int sumx, sumy, sumz;
	if (x < imagesizex && y < imagesizey) // If inside image
	{
// Filter kernel (simple box filter)
	sumx=0;sumy=0;sumz=0;
	for(dy=-kernelsizey;dy<=kernelsizey;dy++)
		for(dx=-kernelsizex;dx<=kernelsizex;dx++)
		{
			// Use max and min to avoid branching!
			int yy = min(max(y+dy, 0), imagesizey-1);
			int xx = min(max(x+dx, 0), imagesizex-1);

			sumx += image[((yy)*imagesizex+(xx))*3+0];
			sumy += image[((yy)*imagesizex+(xx))*3+1];
			sumz += image[((yy)*imagesizex+(xx))*3+2];
		}
	out[(y*imagesizex+x)*3+0] = sumx/divby;
	out[(y*imagesizex+x)*3+1] = sumy/divby;
	out[(y*imagesizex+x)*3+2] = sumz/divby;
	}
  */

}

// Global variables for image data

unsigned char *image, *pixels, *dev_bitmap, *dev_input;
unsigned int imagesizey, imagesizex; // Image size

////////////////////////////////////////////////////////////////////////////////
// main computation function
////////////////////////////////////////////////////////////////////////////////
void computeImages(int kernelsizex, int kernelsizey)
{
	if (kernelsizex > maxKernelSizeX || kernelsizey > maxKernelSizeY)
	{
		printf("Kernel size out of bounds!\n");
		return;
	}

	pixels = (unsigned char *) malloc(imagesizex*imagesizey*3);
	cudaMalloc( (void**)&dev_input, imagesizex*imagesizey*3);
	cudaMemcpy( dev_input, image, imagesizey*imagesizex*3, cudaMemcpyHostToDevice );
	cudaMalloc( (void**)&dev_bitmap, imagesizex*imagesizey*3);

  dim3 grid(imagesizex/SUB_SIZE,imagesizey/SUB_SIZE);
  dim3 block(SUB_SIZE + kernelsizex*2, SUB_SIZE + kernelsizey*2);

	filter<<<grid,block>>>(dev_input, dev_bitmap, imagesizey, imagesizex, kernelsizex, kernelsizey); // Awful load balance
	cudaThreadSynchronize();
//	Check for errors!
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess)
        printf("Error: %s\n", cudaGetErrorString(err));
	cudaMemcpy( pixels, dev_bitmap, imagesizey*imagesizex*3, cudaMemcpyDeviceToHost );
	cudaFree( dev_bitmap );
	cudaFree( dev_input );
}

// Display images
void Draw()
{
// Dump the whole picture onto the screen.
	glClearColor( 0.0, 0.0, 0.0, 1.0 );
	glClear( GL_COLOR_BUFFER_BIT );

	if (imagesizey >= imagesizex)
	{ // Not wide - probably square. Original left, result right.
		glRasterPos2f(-1, -1);
		glDrawPixels( imagesizex, imagesizey, GL_RGB, GL_UNSIGNED_BYTE, image );
		glRasterPos2i(0, -1);
		glDrawPixels( imagesizex, imagesizey, GL_RGB, GL_UNSIGNED_BYTE,  pixels);
	}
	else
	{ // Wide image! Original on top, result below.
		glRasterPos2f(-1, -1);
		glDrawPixels( imagesizex, imagesizey, GL_RGB, GL_UNSIGNED_BYTE, pixels );
		glRasterPos2i(-1, 0);
		glDrawPixels( imagesizex, imagesizey, GL_RGB, GL_UNSIGNED_BYTE, image );
	}
	glFlush();
}

// Main program, inits
int main( int argc, char** argv)
{
	glutInit(&argc, argv);
	glutInitDisplayMode( GLUT_SINGLE | GLUT_RGBA );

	if (argc > 1)
		image = readppm(argv[1], (int *)&imagesizex, (int *)&imagesizey);
	else
		image = readppm((char *)"maskros512.ppm", (int *)&imagesizex, (int *)&imagesizey);

	if (imagesizey >= imagesizex)
		glutInitWindowSize( imagesizex*2, imagesizey );
	else
		glutInitWindowSize( imagesizex, imagesizey*2 );
	glutCreateWindow("Lab 5");
	glutDisplayFunc(Draw);

	ResetMilli();

	computeImages(FILTER_RAD, FILTER_RAD);

// You can save the result to a file like this:
//	writeppm("out.ppm", imagesizey, imagesizex, pixels);

	glutMainLoop();
	return 0;
}