#include "impch.h"
#ifdef IMAGINE_OPENGL
#include "Renderer/Texture.h"

#include <stb_image.h>

#include <glad/glad.h>

namespace IM {

	namespace {
		GLenum _InternalFormat, _DataFormat;
	}
	
	Texture2D::Texture2D(const std::string& path) {
		IMAGINE_PROFILE_FUNCTION();

		int width, height, channels;
		stbi_set_flip_vertically_on_load(1);
		stbi_uc* data = nullptr;
		{
			IMAGINE_PROFILE_SCOPE("stbi_load - OpenGLTexture2D::OpenGLTexture2D(const std::string&)");
			data = stbi_load(path.c_str(), &width, &height, &channels, 0);

		}
		IMAGINE_CORE_ASSERT(data, "Failed to load image in OpenGLTexture2D constructor!");
		_Width = width;
		_Height = height;

		GLenum internalFormat = 0, dataFormat = 0;

		if (channels == 4) {
			internalFormat = GL_RGBA8;
			dataFormat = GL_RGBA;
		}
		else if (channels == 3) {
			internalFormat = GL_RGB8;
			dataFormat = GL_RGB;
		}

		IMAGINE_CORE_ASSERT(internalFormat, "Texture format not supported in OpenGLTexture2D: {}");
		IMAGINE_CORE_ASSERT(dataFormat, "Texture format not supported in OpenGLTexture2D: {}");

		_InternalFormat = internalFormat;
		_DataFormat = dataFormat;

		glCreateTextures(GL_TEXTURE_2D, 1, &_TextureID);
		glTextureStorage2D(_TextureID, 1, internalFormat, _Width, _Height);

		glTextureParameteri(_TextureID, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTextureParameteri(_TextureID, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

		glTextureParameteri(_TextureID, GL_TEXTURE_WRAP_S, GL_REPEAT);
		glTextureParameteri(_TextureID, GL_TEXTURE_WRAP_T, GL_REPEAT);

		glTextureSubImage2D(_TextureID, 0, 0, 0, _Width, _Height, dataFormat, GL_UNSIGNED_BYTE, data);

		stbi_image_free(data);
	}

	Texture2D::Texture2D(uint32_t width, uint32_t height) 
		: _Width(width), _Height(height){

		IMAGINE_PROFILE_FUNCTION();

		_InternalFormat = GL_RGBA8;
		_DataFormat = GL_RGBA;

		glCreateTextures(GL_TEXTURE_2D, 1, &_TextureID);
		glTextureStorage2D(_TextureID, 1, _InternalFormat, _Width, _Height);

		glTextureParameteri(_TextureID, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTextureParameteri(_TextureID, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

		glTextureParameteri(_TextureID, GL_TEXTURE_WRAP_S, GL_REPEAT);
		glTextureParameteri(_TextureID, GL_TEXTURE_WRAP_T, GL_REPEAT);
	}
	
	Texture2D::~Texture2D() {
		IMAGINE_PROFILE_FUNCTION();

		glDeleteTextures(1, &_TextureID);
	}
	
	void Texture2D::SetData(void* data, uint32_t size) {
		IMAGINE_PROFILE_FUNCTION();

		glTextureSubImage2D(_TextureID, 0, 0, 0, _Width, _Height, _DataFormat, GL_UNSIGNED_BYTE, data);
	}
	
	void Texture2D::Bind(uint32_t slot) const {
		IMAGINE_PROFILE_FUNCTION();

		glBindTextureUnit(slot, _TextureID);
	}
	
	void Texture2D::Unbind(uint32_t slot) const {
		glBindTexture(GL_TEXTURE_2D, 0);
	}
}
#endif