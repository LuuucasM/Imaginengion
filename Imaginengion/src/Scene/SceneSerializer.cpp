#include "impch.h"
#include "SceneSerializer.h"

#include "ECS/Entity.h"

#include "ECS/Components.h"

#include <yaml-cpp/yaml.h>

namespace YAML {
	template<>
	struct convert<glm::vec2>
	{
		static Node encode(const glm::vec2& rhs)
		{
			Node node;
			node.push_back(rhs.x);
			node.push_back(rhs.y);
			node.SetStyle(EmitterStyle::Flow);
			return node;
		}

		static bool decode(const Node& node, glm::vec2& rhs)
		{
			if (!node.IsSequence() || node.size() != 2)
				return false;

			rhs.x = node[0].as<float>();
			rhs.y = node[1].as<float>();
			return true;
		}
	};

	template<>
	struct convert<glm::vec3>
	{
		static Node encode(const glm::vec3& rhs)
		{
			Node node;
			node.push_back(rhs.x);
			node.push_back(rhs.y);
			node.push_back(rhs.z);
			node.SetStyle(EmitterStyle::Flow);
			return node;
		}

		static bool decode(const Node& node, glm::vec3& rhs)
		{
			if (!node.IsSequence() || node.size() != 3)
				return false;

			rhs.x = node[0].as<float>();
			rhs.y = node[1].as<float>();
			rhs.z = node[2].as<float>();
			return true;
		}
	};

	template<>
	struct convert<glm::vec4>
	{
		static Node encode(const glm::vec4& rhs)
		{
			Node node;
			node.push_back(rhs.x);
			node.push_back(rhs.y);
			node.push_back(rhs.z);
			node.push_back(rhs.w);
			node.SetStyle(EmitterStyle::Flow);
			return node;
		}

		static bool decode(const Node& node, glm::vec4& rhs)
		{
			if (!node.IsSequence() || node.size() != 4)
				return false;

			rhs.x = node[0].as<float>();
			rhs.y = node[1].as<float>();
			rhs.z = node[2].as<float>();
			rhs.w = node[3].as<float>();
			return true;
		}
	};
}

namespace IM {

	YAML::Emitter& operator<<(YAML::Emitter& out, const glm::vec2& v) {
		out << YAML::Flow;
		out << YAML::BeginSeq << v.x << v.y << YAML::EndSeq;
		return out;
	}

	YAML::Emitter& operator<<(YAML::Emitter& out, const glm::vec3& v) {
		out << YAML::Flow;
		out << YAML::BeginSeq << v.x << v.y << v.z << YAML::EndSeq;
		return out;
	}

	YAML::Emitter& operator<<(YAML::Emitter& out, const glm::vec4& v) {
		out << YAML::Flow;
		out << YAML::BeginSeq << v.x << v.y << v.z << v.w << YAML::EndSeq;
		return out;
	}

	namespace {
		std::string RigidBody2DBodyTypeToString(C_RigidBody2D::BodyType bodyType) {
			switch (bodyType) {
				case C_RigidBody2D::BodyType::Static: return "Static";
				case C_RigidBody2D::BodyType::Dynamic: return "Dynamic";
				case C_RigidBody2D::BodyType::Kinematic: return "Kinematic";
			}
			IMAGINE_CORE_ASSERT(0, "Unknown bodyType in RigidBody2DBodyTypeToString!");
			return {};
		}
		C_RigidBody2D::BodyType RigidBody2DBodyTypeFromString(const std::string& bodyTypeString) {
			if (bodyTypeString == "Static") return C_RigidBody2D::BodyType::Static;
			if (bodyTypeString == "Dynamic") return C_RigidBody2D::BodyType::Dynamic;
			if (bodyTypeString == "Kinematic") return C_RigidBody2D::BodyType::Kinematic;
			IMAGINE_CORE_ASSERT(0, "Unknown bodyTypeString in RigidBody2DBodyTypeFromString!");
			return C_RigidBody2D::BodyType::Static;
		}
	}

	SceneSerializer::SceneSerializer(const RefPtr<Scene>& scene)
		: _Scene(scene){

	}

	static void SerializeEntity(YAML::Emitter& out, Entity& entity) {
		out << YAML::BeginMap;
		out << YAML::Key << "Entity" << YAML::Value << entity.GetUUID();

		if (entity.HasComponent<C_Name>()) {
			out << YAML::Key << "Name Component";

			out << YAML::BeginMap;
			auto& name = entity.GetComponent<C_Name>().Name;
			out << YAML::Key << "Name" << YAML::Value << name;
			out << YAML::EndMap;
		}

		if (entity.HasComponent<C_Transform>()) {
			out << YAML::Key << "Transform Component";
			
			out << YAML::BeginMap;
			auto& transform = entity.GetComponent<C_Transform>();
			out << YAML::Key << "Translation" << YAML::Value << transform.Translation;
			out << YAML::Key << "Rotation" << YAML::Value << transform.Rotation;
			out << YAML::Key << "Scale" << YAML::Value << transform.Scale;
			out << YAML::EndMap;
		}

		if (entity.HasComponent<C_Camera>()) {
			out << YAML::Key << "Camera Component";

			out << YAML::BeginMap;
			auto& camera = entity.GetComponent<C_Camera>();
			out << YAML::Key << "Camera" << YAML::Value;
			out << YAML::BeginMap;
			out << YAML::Key << "ProjectionType" << YAML::Value << (int)camera.Type;
			out << YAML::Key << "PerspectiveFOV" << YAML::Value << camera.PerspectiveFOV;
			out << YAML::Key << "PerspectiveNear" << YAML::Value << camera.PerspectiveicNear;
			out << YAML::Key << "PerspectiveFar" << YAML::Value << camera.PerspectiveFar;
			out << YAML::Key << "OrthographicSize" << YAML::Value << camera.OrthographicSize;
			out << YAML::Key << "OrthographicNear" << YAML::Value << camera.OrthographicNear;
			out << YAML::Key << "OrthographicFar" << YAML::Value << camera.OrthographicFar;
			out << YAML::EndMap;

			out << YAML::Key << "Primary" << YAML::Value << camera.bPrimary;
			out << YAML::Key << "FixedAspectRatio" << YAML::Value << camera.bFixedAspectRatio;
			out << YAML::EndMap;
		}
		if (entity.HasComponent<C_SpriteRenderer>()) {
			out << YAML::Key << "Sprite Renderer Component";

			out << YAML::BeginMap;
			auto& spriteRenderer = entity.GetComponent<C_SpriteRenderer>();
			out << YAML::Key << "Color" << YAML::Value << spriteRenderer.Color;
			out << YAML::EndMap;
		}
		if (entity.HasComponent<C_CircleRenderer>()) {
			out << YAML::Key << "Circle Renderer Component";

			out << YAML::BeginMap;
			auto& circleRenderer = entity.GetComponent<C_CircleRenderer>();
			out << YAML::Key << "Color" << YAML::Value << circleRenderer.Color;
			out << YAML::Key << "Thickness" << YAML::Value << circleRenderer.Thickness;
			out << YAML::Key << "Fade" << YAML::Value << circleRenderer.Fade;
			out << YAML::EndMap;
		}
		if (entity.HasComponent<C_RigidBody2D>()) {
			out << YAML::Key << "Rigid Body 2D";

			out << YAML::BeginMap;
			auto& rigidBody = entity.GetComponent<C_RigidBody2D>();
			out << YAML::Key << "BodyType" << YAML::Value << RigidBody2DBodyTypeToString(rigidBody.Type);
			out << YAML::Key << "FixedRotation" << YAML::Value << rigidBody.bFixedRotation;
			out << YAML::EndMap;
		}
		if (entity.HasComponent<C_RectCollider2D>()) {
			out << YAML::Key << "RectCollider 2D";

			out << YAML::BeginMap;
			auto& collider = entity.GetComponent<C_RectCollider2D>();
			out << YAML::Key << "Offset" << YAML::Value << collider.Offset;
			out << YAML::Key << "Size" << YAML::Value << collider.Size;
			out << YAML::Key << "Density" << YAML::Value << collider.Density;
			out << YAML::Key << "Friction" << YAML::Value << collider.Friction;
			out << YAML::Key << "Restitution" << YAML::Value << collider.Restitution;
			out << YAML::Key << "RestitutionThreshold" << YAML::Value << collider.RestitutionThreshold;
			out << YAML::EndMap;
		}
		if (entity.HasComponent<C_CircleCollider2D>()) {
			out << YAML::Key << "CircleCollider 2D";

			out << YAML::BeginMap;
			auto& collider = entity.GetComponent<C_CircleCollider2D>();
			out << YAML::Key << "Offset" << YAML::Value << collider.Offset;
			out << YAML::Key << "Radius" << YAML::Value << collider.Radius;
			out << YAML::Key << "Density" << YAML::Value << collider.Density;
			out << YAML::Key << "Friction" << YAML::Value << collider.Friction;
			out << YAML::Key << "Restitution" << YAML::Value << collider.Restitution;
			out << YAML::Key << "RestitutionThreshold" << YAML::Value << collider.RestitutionThreshold;
			out << YAML::EndMap;
		}

		out << YAML::EndMap;
	}

	void SceneSerializer::SerializeText(const std::string& filepath)
	{
		YAML::Emitter out;
		out << YAML::BeginMap;
		out << YAML::Key << "Scene" << YAML::Value << _Scene->_Name;
		out << YAML::Key << "Entities";
		out << YAML::Value << YAML::BeginSeq;
		std::unordered_set<uint32_t>& entities = _Scene->_ECSManager.GetAllEntityID();
		for (auto ent : entities) {
			Entity entity = { ent, _Scene.get() };
			SerializeEntity(out, entity);
		}
		out << YAML::EndSeq;
		out << YAML::EndMap;

		std::ofstream fout(filepath);
		fout << out.c_str();

	}
	void SceneSerializer::SerializeRuntime(const std::string& filepath)
	{
		//not implemented
		IMAGINE_CORE_ASSERT(false, "");
	}
	bool SceneSerializer::DeSerializeText(const std::string& filepath)
	{
		YAML::Node data = YAML::LoadFile(filepath);
		if (!data["Scene"]) {
			return false;
		}
		std::string sceneName = data["Scene"].as<std::string>();
		_Scene->SetName(sceneName);
		IMAGINE_CORE_TRACE("Deserializing scene '{}'", sceneName);

		auto entities = data["Entities"];
		if (entities) {
			for (auto entity : entities) {
				uint64_t uuid = entity["Entity"].as<uint64_t>();

				std::string name;
				auto nameComponent = entity["Name Component"];
				if (nameComponent) {
					name = nameComponent["Name"].as<std::string>();
				}

				IMAGINE_CORE_TRACE("Deserialized entity with ID = {}, name = {}", uuid, name);

				Entity e = _Scene->CreateEntityWithUUID(uuid, name);
				
				auto transformComponent = entity["Transform Component"];
				if (transformComponent) {
					auto& transform = e.GetComponent<C_Transform>();
					transform.Translation = transformComponent["Translation"].as<glm::vec3>();
					transform.Rotation = transformComponent["Rotation"].as<glm::vec3>();
					transform.Scale = transformComponent["Scale"].as<glm::vec3>();
				}

				auto cameraComponent = entity["Camera Component"];
				if (cameraComponent) {
					auto& cc = e.AddComponent<C_Camera>();
					auto cameraProps = cameraComponent["Camera"];
					cc.Type = (IM::C_Camera::ProjectionType)cameraProps["ProjectionType"].as<int>();

					cc.PerspectiveFOV = cameraProps["PerspectiveFOV"].as<float>();
					cc.PerspectiveicNear = cameraProps["PerspectiveNear"].as<float>();
					cc.PerspectiveFar = cameraProps["PerspectiveFar"].as<float>();
					cc.OrthographicSize = cameraProps["OrthographicSize"].as<float>();
					cc.OrthographicNear = cameraProps["OrthographicNear"].as<float>();
					cc.OrthographicFar = cameraProps["OrthographicFar"].as<float>();

					cc.bPrimary = cameraComponent["Primary"].as<bool>();
					cc.bFixedAspectRatio = cameraComponent["FixedAspectRatio"].as<bool>();
				}

				auto spriteRendererComponent = entity["Sprite Renderer Component"];
				if (spriteRendererComponent) {
					auto& src = e.AddComponent<C_SpriteRenderer>();
					src.Color = spriteRendererComponent["Color"].as<glm::vec4>();
				}

				auto circleRendererComponent = entity["Circle Renderer Component"];
				if (circleRendererComponent) {
					auto& crc = e.AddComponent<C_CircleRenderer>();
					crc.Color = circleRendererComponent["Color"].as<glm::vec4>();
					crc.Thickness = circleRendererComponent["Thickness"].as<float>();
					crc.Fade = circleRendererComponent["Fade"].as<float>();
				}

				auto rigidBody = entity["Rigid Body 2D"];
				if (rigidBody) {
					auto& rb = e.AddComponent<C_RigidBody2D>();
					rb.Type = RigidBody2DBodyTypeFromString(rigidBody["BodyType"].as<std::string>());
					rb.bFixedRotation = rigidBody["FixedRotation"].as<bool>();
				}

				auto rectCollider = entity["RectCollider 2D"];
				if (rectCollider) {
					auto& rc = e.AddComponent<C_RectCollider2D>();
					rc.Offset = rectCollider["Offset"].as<glm::vec2>();
					rc.Size = rectCollider["Size"].as<glm::vec2>();
					rc.Density = rectCollider["Density"].as<float>();
					rc.Friction = rectCollider["Friction"].as<float>();
					rc.Restitution = rectCollider["Restitution"].as<float>();
					rc.RestitutionThreshold = rectCollider["RestitutionThreshold"].as<float>();
				}
				auto circleCollider = entity["CircleCollider 2D"];
				if (circleCollider) {
					auto& cc = e.AddComponent<C_CircleCollider2D>();
					cc.Offset = circleCollider["Offset"].as<glm::vec2>();
					cc.Radius = circleCollider["Radius"].as<float>();
					cc.Density = circleCollider["Density"].as<float>();
					cc.Friction = circleCollider["Friction"].as<float>();
					cc.Restitution = circleCollider["Restitution"].as<float>();
					cc.RestitutionThreshold = circleCollider["RestitutionThreshold"].as<float>();
				}
			}
		}
		return true;
	}
	bool SceneSerializer::DeSerializeRuntime(const std::string& filepath)
	{
		//not implemented
		IMAGINE_CORE_ASSERT(false, "");
		return false;
	}
}