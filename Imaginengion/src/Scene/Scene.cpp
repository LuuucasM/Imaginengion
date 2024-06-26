#include "impch.h"
#include "Scene.h"

#include "SceneSerializer.h"

#include "ECS/Components.h"
#include "ECS/Components/ScriptClass.h"
#include "ECS/Systems.h"
#include "Renderer/Renderer.h"

#include <glm/glm.hpp>

#include "ECS/Entity.h"

#include "box2d/b2_world.h"
#include "box2d/b2_body.h"
#include "box2d/b2_fixture.h"
#include "box2d/b2_polygon_shape.h"
#include "box2d/b2_circle_shape.h"


namespace IM {

	namespace {
		b2BodyType RigidBody2DTypeToBox2DType(C_RigidBody2D::BodyType bodyType) {
			switch (bodyType) {
				case C_RigidBody2D::BodyType::Static: return b2_staticBody;
				case C_RigidBody2D::BodyType::Dynamic: return b2_dynamicBody;
				case C_RigidBody2D::BodyType::Kinematic: return b2_kinematicBody;
			}
			IMAGINE_CORE_ASSERT(0, "Unknown Body Type in RigidBody2DTypeToBox2D!");
			return b2_staticBody;
		}

		template<typename C_Type>
		void CopyComponentIfExists(Entity newEntity, Entity oldEntity) {
			if (oldEntity.HasComponent<C_Type>()) {
				newEntity.AddComponent(oldEntity.GetComponent<C_Type>());
			}
		}
	}

	Scene::Scene()
	{
		_ECSManager.RegisterComponent<C_Transform>();
		_ECSManager.RegisterComponent<C_SpriteRenderer>();
	}
	Scene::~Scene()
	{
	}
	RefPtr<Scene> Scene::Copy(RefPtr<Scene> other)
	{
		SceneSerializer oldSerializer(other);
		std::filesystem::path tempPath("./tmp.imsc");
		oldSerializer.SerializeText(tempPath.string());

		RefPtr<Scene> newScene = CreateRefPtr<Scene>();
		SceneSerializer newSerializer(newScene);
		newSerializer.DeSerializeText(tempPath.string());
		std::remove(tempPath.string().c_str());

		newScene->OnViewportResize(other->_ViewportWidth, other->_ViewportHeight);
		return newScene;
	}
	Entity Scene::CreateEntity(const std::string& name)
	{
		return CreateEntityWithUUID(UUID(), name);
	}
	Entity Scene::CreateEntityWithUUID(UUID uuid, const std::string& name)
	{
		Entity e = { _ECSManager.CreateEntity(), this };
		e.AddComponent<C_ID>(uuid);
		e.AddComponent<C_Name>(name);
		e.AddComponent<C_Transform>();
		return e;
	}
	void Scene::DestroyEntity(Entity entity)
	{
		_ECSManager.DestroyEntity(entity);
	}
	Entity Scene::DuplicateEntity(Entity oldEntity)
	{
		Entity newEntity = CreateEntity(oldEntity.GetName());
		CopyComponentIfExists<C_Transform>(newEntity, oldEntity);
		CopyComponentIfExists<C_SpriteRenderer>(newEntity, oldEntity);
		CopyComponentIfExists<C_CircleRenderer>(newEntity, oldEntity);
		CopyComponentIfExists<C_Camera>(newEntity, oldEntity);
		CopyComponentIfExists<C_NativeScript>(newEntity, oldEntity);
		CopyComponentIfExists<C_RigidBody2D>(newEntity, oldEntity);
		CopyComponentIfExists<C_RectCollider2D>(newEntity, oldEntity);
		CopyComponentIfExists<C_CircleCollider2D>(newEntity, oldEntity);
		return newEntity;

	}
	void Scene::OnRuntimeStart()
	{
		_PhysicsWorld = CreateScopePtr<b2World>(b2Vec2{ 0.0f, -9.81f });
		auto& group = _ECSManager.GetGroup<C_RigidBody2D>();
		for (auto e : group) {
			Entity entity = { e, this };
			auto& transform = entity.GetComponent<C_Transform>();
			auto& rb2d = entity.GetComponent<C_RigidBody2D>();

			b2BodyDef bodyDef;
			bodyDef.type = RigidBody2DTypeToBox2DType(rb2d.Type);
			bodyDef.position.Set(transform.Translation.x, transform.Translation.y);
			bodyDef.angle = transform.Rotation.z;

			b2Body *body = _PhysicsWorld->CreateBody(&bodyDef);
			body->SetFixedRotation(rb2d.bFixedRotation);
			rb2d.RuntimeBody = body;

			if (entity.HasComponent<C_RectCollider2D>()) {
				auto& bc2d = entity.GetComponent<C_RectCollider2D>();

				b2PolygonShape polygonShape;
				polygonShape.SetAsBox(bc2d.Size.x * transform.Scale.x, bc2d.Size.y * transform.Scale.y);

				b2FixtureDef fixtureDef;
				fixtureDef.shape = &polygonShape;
				fixtureDef.density = bc2d.Density;
				fixtureDef.friction = bc2d.Friction;
				fixtureDef.restitution = bc2d.Restitution;
				fixtureDef.restitutionThreshold = bc2d.RestitutionThreshold;
				body->CreateFixture(&fixtureDef);
			}
			if (entity.HasComponent<C_CircleCollider2D>()) {
				auto& cc2d = entity.GetComponent<C_CircleCollider2D>();

				b2CircleShape circleShape;
				circleShape.m_p.Set(cc2d.Offset.x, cc2d.Offset.y);
				circleShape.m_radius = cc2d.Radius;

				b2FixtureDef fixtureDef;
				fixtureDef.shape = &circleShape;
				fixtureDef.density = cc2d.Density;
				fixtureDef.friction = cc2d.Friction;
				fixtureDef.restitution = cc2d.Restitution;
				fixtureDef.restitutionThreshold = cc2d.RestitutionThreshold;
				body->CreateFixture(&fixtureDef);
			}
		}
	}
	void Scene::OnRuntimeStop()
	{
		_PhysicsWorld.reset();
	}
	void Scene::OnUpdateRuntime(float dt)
	{
		_FPS = 1.0f / dt;
		//update scripts on update function
		//SCRIPTS SYSTEM
		auto& scripts = _ECSManager.GetGroup<C_NativeScript>();
		for (auto entity : scripts) {
			auto& script = _ECSManager.GetComponent<C_NativeScript>(entity);
			if (!script.Instance) {
				script.Instance = script.CreateScript();
				script.Instance->_Entity = { entity, this };
				script.Instance->OnCreate();
			}
			script.Instance->OnUpdate(dt);
		}

		//update physics
		//PHYSTICS SYSTEm
		const int32_t velocityIterations = 6;
		const int32_t positionIterations = 2;
		_PhysicsWorld->Step(dt, velocityIterations, positionIterations);

		auto& rigidbodys = _ECSManager.GetGroup<C_RigidBody2D>();
		for (auto e : rigidbodys) {
			Entity entity = { e, this };
			auto& transform = entity.GetComponent<C_Transform>();
			auto& rb2d = entity.GetComponent<C_RigidBody2D>();

			b2Body* body = static_cast<b2Body*>(rb2d.RuntimeBody);
			const auto& position = body->GetPosition();
			transform.Translation.x = position.x;
			transform.Translation.y = position.y;
			transform.Rotation.z = body->GetAngle();
		}

		//CHECKING TO SEE IF WE HAVE DEFINED A PRIMARY CAMERA
		//need to change this so that scene just directly holds a pointer to the primary camera instead of looping through cameras every time
		C_Camera *mainCamera = nullptr;
		C_Transform* cameraTransform = nullptr;
		auto& entities = _ECSManager.GetGroup<C_Transform, C_Camera>();
		for (auto ent : entities) {
			auto ent_cam = _ECSManager.GetComponent<C_Camera>(ent);
			if (ent_cam.bPrimary) {
				mainCamera = &ent_cam;
				cameraTransform = &_ECSManager.GetComponent<C_Transform>(ent);
				break;
			}
		}

		if (mainCamera) {
			//RENDER SYSTEM
			Renderer::R2D::BeginScene(*mainCamera, *cameraTransform);

			{
				auto& group = _ECSManager.GetGroup<C_Transform, C_SpriteRenderer>();
				for (auto entity : group) {
					auto [transform, sprite] = _ECSManager.GetComponents<C_Transform, C_SpriteRenderer>(entity);
					Renderer::R2D::DrawSprite(transform.GetTransform(), sprite, entity);
				}
			}

			{
				auto& group = _ECSManager.GetGroup<C_Transform, C_CircleRenderer>();
				for (auto entity : group) {
					auto [transform, circle] = _ECSManager.GetComponents<C_Transform, C_CircleRenderer>(entity);
					Renderer::R2D::DrawCircle(transform.GetTransform(), circle.Color, circle.Thickness, circle.Fade, entity);
				}
			}
			Renderer::R2D::EndScene();
		}
	}
	void Scene::OnUpdateEditor(float dt, EditorCamera& camera)
	{
		_FPS = 1.0f / dt;
		//RENDER SYSTEM
		Renderer::R2D::BeginScene(camera);
		{
			auto& group = _ECSManager.GetGroup<C_Transform, C_SpriteRenderer>();
			for (auto entity : group) {
				auto [transform, sprite] = _ECSManager.GetComponents<C_Transform, C_SpriteRenderer>(entity);
				Renderer::R2D::DrawSprite(transform.GetTransform(), sprite, entity);
			}
		}

		{
			auto& group = _ECSManager.GetGroup<C_Transform, C_CircleRenderer>();
			for (auto entity : group) {
				auto [transform, circle] = _ECSManager.GetComponents<C_Transform, C_CircleRenderer>(entity);
				Renderer::R2D::DrawCircle(transform.GetTransform(), circle.Color, circle.Thickness, circle.Fade, entity);
			}
		}
		Renderer::R2D::EndScene();
	}
	void Scene::OnViewportResize(size_t viewportWidth, size_t viewportHeight)
	{
		_ViewportWidth = viewportWidth;
		_ViewportHeight = viewportHeight;

		//this is a changing aspect ratio on cameras depending on viewport resizeing
		auto& entities = _ECSManager.GetGroup<C_Camera>();
		for (auto ent : entities) {
			//auto& cam = _ECSManager.GetComponent<C_Camera>(ent);
			auto [transform, cam] = _ECSManager.GetComponents<C_Transform, C_Camera>(ent);
			if (!cam.bFixedAspectRatio) {
				cam.SetViewportSize(viewportWidth, viewportHeight);
			}
		}
	}

	Entity Scene::GetPrimaryCameraEntity()
	{
		auto& group = _ECSManager.GetGroup<C_Camera>();
		for (auto entity : group) {
			auto& cameraComponent = _ECSManager.GetComponent<C_Camera>(entity);
			if (cameraComponent.bPrimary) {
				return Entity(entity, this);
			}
		}
		return { 0, nullptr };
	}

	template<typename T>
	void Scene::OnComponentAdded(Entity entity, T& component) {
		IMAGINE_CORE_ASSERT(0, "this should never happen! in OnComponentAdded")
	}

	template<>
	void Scene::OnComponentAdded<C_ID>(Entity entity, C_ID& component) {

	}

	template<>
	void Scene::OnComponentAdded<C_Transform>(Entity entity, C_Transform& component) {
		
	}
	template<>
	void Scene::OnComponentAdded<C_SpriteRenderer>(Entity entity, C_SpriteRenderer& component) {

	}
	template<>
	void Scene::OnComponentAdded<C_CircleRenderer>(Entity entity, C_CircleRenderer& component) {

	}
	template<>
	void Scene::OnComponentAdded<C_Name>(Entity entity, C_Name& component) {

	}
	template<>
	void Scene::OnComponentAdded<C_Camera>(Entity entity, C_Camera& component) {
		if (_ViewportWidth > 0 && _ViewportHeight > 0) {
			component.SetViewportSize(_ViewportWidth, _ViewportHeight);
		}
	}
	template<>
	void Scene::OnComponentAdded<C_NativeScript>(Entity entity, C_NativeScript& component) {

	}
	template<>
	void Scene::OnComponentAdded<C_RigidBody2D>(Entity entity, C_RigidBody2D& component) {

	}
	template<>
	void Scene::OnComponentAdded<C_RectCollider2D>(Entity entity, C_RectCollider2D& component) {

	}
	template<>
	void Scene::OnComponentAdded<C_CircleCollider2D>(Entity entity, C_CircleCollider2D& component) {

	}
}