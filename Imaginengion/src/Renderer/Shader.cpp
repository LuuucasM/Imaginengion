#include "impch.h"
#include "Shader.h"

#include "RendererAPI.h"
#include "Platform/OpenGL/OpenGLShader.h"

namespace IM {
	RefPtr<Shader> Shader::Create(const std::string& filepath) {
		switch (RendererAPI::GetCurrentAPI()) {
		case RendererAPI::API::None:
			IMAGINE_CORE_ASSERT(false, "RendererAPI::API::None is currently not supported !");
			return nullptr;
		case RendererAPI::API::OpenGL:
			return  CreateRefPtr<OpenGLShader>(filepath);
		}
		IMAGINE_CORE_ASSERT(false, "Unknown RendererAPI!");
		return nullptr;
	}
}