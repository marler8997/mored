module more.gl;

import std.stdio;
import std.conv;
import std.string;

import glad.gl.enums;
import glad.gl.funcs;
import glad.gl.ext;
import glad.gl.loader;
import glad.gl.types;

import gl3n.linalg;

import more.common;

struct Vector2i
{
  int x,y;
}
struct Vector2f
{
  align(4):
  float x,y;

  this(float x, float y)
  {
    this.x = x;
    this.y = y;
  }
}
struct Vector3f
{
  align(4):
  float x,y,z;
  this(float x, float y, float z)
  {
    this.x = x;
    this.y = y;
    this.z = z;
  }
}

/// Reads the shader source code and appends a NULL character
/// to the end of it so it can be passed to glShaderSource
char[] readGLShader(string filename)
{
  File file = File(filename);
  scope(exit) file.close();

  ulong fileSizeULong = file.size();
  fileSizeULong++; // Add 1 for the ending NULL character
  if(fileSizeULong > uint.max) throw new Exception(format(
    "File '%s' is too large (%s bytes including the ending NULL)", filename, fileSizeULong));

  char[] contents = new char[cast(uint)fileSizeULong];
  file.readFullSize(contents[0..$-1]);
  contents[$-1] = '\0';

  return contents;
}


unittest
{
  startTest("readFileToCStrings");
  endTest("readFileToCStrings");
}

uint loadShader(GLenum type, string filename)
{
  return loadShader(type, filename, readGLShader(filename).ptr);
}
uint loadShader(GLenum type, string shaderName, const(char*) source)
{
  char[512] error;

  uint id = glCreateShader(type);
  if(id == 0) throw new Exception("glCreateShader failed");
  scope(failure) glDeleteShader(id);

  glShaderSource(id, 1, &source, null);
  glCompileShader(id);

  int errorLength;
  glGetShaderInfoLog(id, error.length, &errorLength, error.ptr);

  if(errorLength) {
    char[] msg = "Failed to compile shader '" ~ shaderName ~ "': " ~ error[0..core.stdc.string.strlen(error.ptr)];
    throw new Exception(to!string(msg));
  }
  return id;
}


struct ShaderVar
{
  string name;
  immutable(char)* zname;

  GLint location;

  this(string name)
  {
    this.name = name;
    this.zname = name.toStringz();
  }
}

struct ShaderProgram
{
  uint id;

  void init()
  {
    this.id = glCreateProgram();
    if(this.id == 0) throw new Exception("glCreateProgram failed");
  }
  void attachShader(GLenum type, string filename)
  {
    if(id == 0) init();
    attachShader(loadShader(type, filename));
  }
  void attachShader(GLenum type, string shaderName, const(char*) source)
  {
    if(id == 0) init();
    attachShader(loadShader(type, shaderName, source));
  }
  void attachShader(uint shaderID)
  {
    if(id == 0) init();
    glAttachShader(id, shaderID);
    // TODO: check for errors
  }
  void link()
  {
    if(id == 0) throw new Exception("Cannot link until you attach shaders");

    glLinkProgram(id);
    int linkResult;
    glGetProgramiv(id, GL_LINK_STATUS, &linkResult);
    if(linkResult == GL_FALSE) throw new Exception("Failed to link shader program");
  }

  void use()
  {
    glUseProgram(id);
  }

/+
  GLint getUniformLocation(string name)
  {
    GLint location = glGetUniformLocation(id, name);
    if(location == -1) throw new Exception("Failed to get uniform '" ~ name ~ "' variable location");
  }
+/
  GLint getUniformLocation(const(char)* name)
  {
    GLint location = glGetUniformLocation(id, name);
    if(location == -1) throw new Exception("Failed to get uniform '" ~ to!string(name) ~ "' variable location");
    return location;
  }
/+
  GLint getAttributeLocation(string name)
  {
    GLint location = glGetAttribLocation(id, name);
    if(location == -1) throw new Exception("Failed to get attribute '" ~ name ~ "' variable location");
    return location;
  }
+/
  GLint getAttributeLocation(const(char)* name)
  {
    GLint location = glGetAttribLocation(id, name);
    if(location == -1) throw new Exception("Failed to get attribute '" ~ to!string(name) ~ "' variable location");
    return location;
  }

  void getUniformLocations(ShaderVar[] vars...)
  {
    foreach(var; vars) {
      var.location = glGetUniformLocation(id, var.zname);
      if(var.location == -1) throw new Exception("Failed to get uniform '" ~ var.name ~ "' variable location");
    }
  }
  void getAttributeLocations(ShaderVar[] vars...)
  {
    foreach(var; vars) {
      var.location = glGetAttribLocation(id, var.zname);
      if(var.location == -1) throw new Exception("Failed to get attribute '" ~ var.name ~ "' variable location");
    }
  }
}


void perspective(ref mat4 mat, float fieldOfViewYDegrees, float widthToHeightRatio,
                 float zClipNear, float zClipFar)
{

  float yMax = zClipNear * tan(fieldOfViewYDegrees * PI / 360);
  float xMax = yMax * widthToHeightRatio;

  frustrum(mat, -xMax, xMax, -yMax, yMax, zClipNear, zClipFar);
}
void frustrum(ref mat4 mat, float left, float right,
              float bottom, float top, float zNear, float zFar)
{
  float temp   = 2 * zNear;
  float width  = right - left;
  float height = top - bottom;
  float depth  = zFar - zNear;

  mat[0][0] = temp / width;
  mat[0][1] = 0;
  mat[0][2] = 0;
  mat[0][3] = 0;

  mat[1][0] = 0;
  mat[1][1] = temp / height;
  mat[1][2] = 0;
  mat[1][3] = 0;

  mat[2][0] = (right + left)  / width;
  mat[2][1] = (top + bottom)  / height;
  mat[2][2] = (-zFar - zNear) / depth;
  mat[2][3] = -1;

  mat[3][0] = 0;
  mat[3][1] = 0;
  mat[3][2] = (-temp * zFar) / depth;
  mat[3][3] = 0;
}
