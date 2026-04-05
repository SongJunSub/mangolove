---
name: Josun Hotel CRS (Central Reservation System)
path: /Users/ltm-luan/Project/CRS
tech_stack: [Java, Kotlin, Spring Boot, JPA, QueryDSL, MySQL, Redis, Kafka]
modules:
  - crs: Core reservation system
  - crs-admin: Admin management service
  - crs-be: Backend API service
  - crs-admin-web: Admin web frontend
  - crs-be-web: Backend web frontend
  - crs-oxi-restarter-agent: OXI restart agent
build_cmd: ./gradlew build
test_cmd: ./gradlew test
---

## Architecture
- Multi-module Spring Boot project
- Hotel reservation and channel management system
- 조선호텔 CRS (Central Reservation System)

## Conventions
- Follow Google Java Style Guide
- Conventional Commits for git messages
- Spring Boot package structure: config / controller / service / repository / domain / dto / exception

## Key Notes
- DB connection info stored in mangolove memory
- Multiple sub-projects that need coordinated changes
