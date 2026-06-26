package com.blaineam.haven.ui

import android.content.Context
import android.graphics.SurfaceTexture
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.util.Log
import com.blaineam.haven.core.FilterShader
import com.blaineam.haven.core.FilterSpec
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/**
 * A live, filter-applied camera preview: the camera frame arrives on an external-OES texture and is
 * drawn through the SAME grading shader the photo/video paths use (just the OES variant). The user
 * can swap the [filterSpec] instantly and see it on the live feed — the Android equivalent of the
 * iOS MetalCameraPreview. Capture stays unfiltered (handled by CameraX outputs); the chosen filter
 * is carried into the editor, exactly like iOS.
 */
class FilteredCameraView(context: Context) : GLSurfaceView(context) {
    private val renderer = CamRenderer()

    /** Invoked (on the main thread) once the camera SurfaceTexture exists — wire CameraX here. */
    var onSurfaceTextureReady: ((SurfaceTexture) -> Unit)? = null

    init {
        setEGLContextClientVersion(2)
        setRenderer(renderer)
        renderMode = RENDERMODE_WHEN_DIRTY
    }

    /** Change the live filter; rebuilds the OES program on the GL thread. */
    fun setFilter(spec: FilterSpec) = queueEvent { renderer.setSpec(spec) }

    /** Tell the renderer the camera frame size so it can aspect-FILL (center-crop) instead of squish. */
    fun setFrameSize(w: Int, h: Int) = queueEvent { renderer.setFrameSize(w, h) }

    private inner class CamRenderer : Renderer, SurfaceTexture.OnFrameAvailableListener {
        private var program = 0
        private var oesTex = 0
        private var surfaceTexture: SurfaceTexture? = null
        private val texMatrix = FloatArray(16)
        private var pendingSpec: FilterSpec = FilterSpec()
        private var builtSpec: FilterSpec? = null

        // Quad: x,y, s,t (triangle strip). Vertices are scaled so the camera frame aspect-FILLS the
        // view (center-crop) — overflow is clipped by the viewport — instead of stretching to fit.
        private val quad: FloatBuffer = ByteBuffer.allocateDirect(16 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        private var viewW = 0; private var viewH = 0
        private var frameW = 0; private var frameH = 0

        init { writeQuad() }

        /** Rebuild the quad vertices so the (portrait) camera content covers the view without distortion. */
        private fun writeQuad() {
            val vA = if (viewH > 0) viewW.toFloat() / viewH else 1f
            // Story camera is portrait: the displayed content aspect is min/max of the buffer dims.
            val cA = if (frameW > 0 && frameH > 0) minOf(frameW, frameH).toFloat() / maxOf(frameW, frameH) else vA
            var sx = 1f; var sy = 1f
            if (cA > vA) sx = cA / vA else if (cA > 0f) sy = vA / cA
            quad.clear()
            quad.put(floatArrayOf(-sx, -sy, 0f, 0f,  sx, -sy, 1f, 0f,  -sx, sy, 0f, 1f,  sx, sy, 1f, 1f))
            quad.position(0)
        }

        fun setFrameSize(w: Int, h: Int) { frameW = w; frameH = h; writeQuad() }

        fun setSpec(spec: FilterSpec) { pendingSpec = spec }

        override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
            val tex = IntArray(1); GLES20.glGenTextures(1, tex, 0)
            oesTex = tex[0]
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTex)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
            buildProgram(pendingSpec)

            val st = SurfaceTexture(oesTex)
            st.setOnFrameAvailableListener(this)
            surfaceTexture = st
            post { onSurfaceTextureReady?.invoke(st) }   // hand the texture to CameraX on the main thread
        }

        override fun onFrameAvailable(st: SurfaceTexture?) = requestRender()

        override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
            GLES20.glViewport(0, 0, width, height)
            viewW = width; viewH = height; writeQuad()
        }

        override fun onDrawFrame(gl: GL10?) {
            val st = surfaceTexture ?: return
            if (pendingSpec != builtSpec) buildProgram(pendingSpec)
            runCatching { st.updateTexImage(); st.getTransformMatrix(texMatrix) }
                .onFailure { return }

            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
            GLES20.glUseProgram(program)
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTex)
            GLES20.glUniform1i(GLES20.glGetUniformLocation(program, "sTexture"), 0)
            GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(program, "uTexMatrix"), 1, false, texMatrix, 0)

            val aPos = GLES20.glGetAttribLocation(program, "aPosition")
            val aTex = GLES20.glGetAttribLocation(program, "aTextureCoord")
            quad.position(0)
            GLES20.glEnableVertexAttribArray(aPos)
            GLES20.glVertexAttribPointer(aPos, 2, GLES20.GL_FLOAT, false, 16, quad)
            quad.position(2)
            GLES20.glEnableVertexAttribArray(aTex)
            GLES20.glVertexAttribPointer(aTex, 2, GLES20.GL_FLOAT, false, 16, quad)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        }

        private fun buildProgram(spec: FilterSpec) {
            if (program != 0) GLES20.glDeleteProgram(program)
            val v = compile(GLES20.GL_VERTEX_SHADER, FilterShader.CAMERA_VERTEX)
            val f = compile(GLES20.GL_FRAGMENT_SHADER, FilterShader.fragmentForOes(spec))
            program = GLES20.glCreateProgram()
            GLES20.glAttachShader(program, v); GLES20.glAttachShader(program, f); GLES20.glLinkProgram(program)
            GLES20.glDeleteShader(v); GLES20.glDeleteShader(f)
            Matrix.setIdentityM(texMatrix, 0)
            builtSpec = spec
        }

        private fun compile(type: Int, src: String): Int {
            val s = GLES20.glCreateShader(type)
            GLES20.glShaderSource(s, src); GLES20.glCompileShader(s)
            val ok = IntArray(1); GLES20.glGetShaderiv(s, GLES20.GL_COMPILE_STATUS, ok, 0)
            if (ok[0] == 0) Log.e("FilteredCameraView", "compile: ${GLES20.glGetShaderInfoLog(s)}")
            return s
        }
    }
}
