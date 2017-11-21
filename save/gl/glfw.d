module more.glfw;

import std.stdio;
import std.conv;

import deimos.glfw.glfw3;

GLFWControls controls;
extern(C) void glfwKeyCallback(GLFWwindow* window, int key, int scancode, int action, int mods) nothrow
{
  controls.keyCallback(key, action, mods);
}
void setControlsToWindow(GLFWwindow* window) {
  glfwSetKeyCallback(window, &glfwKeyCallback);
}
struct GLFWKeyState {
  bool pressed;
  int mods;
}
struct GLFWControls
{
  GLFWKeyState*[int] keyMap;

  public void register(int key, GLFWKeyState *state) {
    GLFWKeyState** keyStateAddress = key in keyMap;
    if(keyStateAddress) throw new Exception("key " ~ to!string(key) ~ " is already registered");
    keyMap[key] = state;
    writefln("Key %d registered", key);
  }
  void keyCallback(int key, int action, int mods) nothrow
  {
    GLFWKeyState** keyStateAddress = key in keyMap;
    if(keyStateAddress) {
      GLFWKeyState *keyState = *keyStateAddress;
      keyState.pressed = action != GLFW_RELEASE;
      keyState.mods = mods;
      //try {writefln("Captured Key code:%d action:%d", key, action);} catch(Exception){}
    } else {
      //try {writefln("Ignored  Key code:%d action:%d", key, action);} catch(Exception){}
    }
  }
}
