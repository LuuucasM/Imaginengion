#pragma once

#include "Core.h"
#pragma warning(push, 0)
#include "spdlog/spdlog.h"
#pragma warning(pop)

namespace IM {
	class Log
	{
	public:
		~Log();
		/*
		* Initialize the logging system. Must be called at start of main function
		*/
		static void Init();

		//retrieve the core and client loggers
		static RefPtr<spdlog::logger> GetCoreLogger() { return CoreLogger; }
		static RefPtr<spdlog::logger> GetClientLogger() { return ClientLogger; }

	private:
		//core and client logger instances for logging
		static RefPtr<spdlog::logger> CoreLogger;
		static RefPtr<spdlog::logger> ClientLogger;
	};
}

//core log macros
#define IMAGINE_CORE_CRITICAL(...) IM::Log::GetCoreLogger()->critical(__VA_ARGS__)
#define IMAGINE_CORE_ERROR(...) IM::Log::GetCoreLogger()->error(__VA_ARGS__)
#define IMAGINE_CORE_WARN(...) IM::Log::GetCoreLogger()->warn(__VA_ARGS__)
#define IMAGINE_CORE_INFO(...) IM::Log::GetCoreLogger()->info(__VA_ARGS__)
#define IMAGINE_CORE_TRACE(...) IM::Log::GetCoreLogger()->trace(__VA_ARGS__)

//client log macros
#define IMAGINE_CRITICAL(...) IM::Log::GetClientLogger()->critical(__VA_ARGS__)
#define IMAGINE_ERROR(...) IM::Log::GetClientLogger()->error(__VA_ARGS__)
#define IMAGINE_WARN(...) IM::Log::GetClientLogger()->warn(__VA_ARGS__)
#define IMAGINE_INFO(...) IM::Log::GetClientLogger()->info(__VA_ARGS__)
#define IMAGINE_TRACE(...) IM::Log::GetClientLogger()->trace(__VA_ARGS__)