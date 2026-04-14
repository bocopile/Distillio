---
# ArgoCD GitOps 패턴 — 학습 가이드
> 생성일: 2026-04-14 | 검증: Gemini + Claude + Codex | 대상: DevOps 엔지니어 (3년 이상)

> **대상 버전:** Argo CD **v3.3.0** 기준 검증 (2026-04-14 현재 GitHub Releases Latest). 하위 호환 참고가 필요하면 v2.13 LTS 문서를 병기합니다. [수정: Codex]

---

## 1. 개념 (Concept) [보강]

### 핵심 개념 정의
ArgoCD는 Kubernetes를 위한 선언적 GitOps 지속적 배포(CD) 도구입니다. Git 저장소를 **Single Source of Truth(SSOT)**로 삼아, 저장소에 정의된 원하는 상태(Desired State)와 클러스터의 실제 상태(Actual State)를 동기화합니다.

### 등장 배경과 해결하는 문제
1. **Configuration Drift 방지:** 수동 운영(`kubectl edit` 등)으로 인해 발생하는 클러스터 설정 오염을 자동 복구(Self-healing) 기능으로 해결합니다.
2. **배포 가시성 확보:** 복잡한 마이크로서비스 아키텍처(MSA)에서 어떤 버전의 코드가 어떤 클러스터에 배포되어 있는지 시각적으로 제공합니다.
3. **Audit 및 롤백:** 모든 변경 사항이 Git 커밋 로그로 남으므로, 장애 발생 시 `git revert`만으로 즉각적인 롤백이 가능합니다.

### 다른 기술과의 비교
| 비교 항목 | ArgoCD (GitOps) | Jenkins (Traditional CD) | FluxCD |
| :--- | :--- | :--- | :--- |
| **방식** | Pull-based (Agent가 감시) | Push-based (Script 실행) | Pull-based |
| **상태 관리** | 실시간 동기화 및 대시보드 | 일회성 작업 (Job 단위) | CLI 위주 상태 관리 |
| **복구** | 자동 (Self-healing) | 수동 재실행 필요 | 자동 (Self-healing) |
| **UI** | 매우 강력한 웹 UI 제공 | 플러그인 기반 UI | Weave GitOps(OSS) UI 안정화 단계 [수정: Claude] |

### ArgoCD 컴포넌트 구조 [수정: Claude]

| 컴포넌트 | 역할 | 스케일링 고려사항 |
| :--- | :--- | :--- |
| **API Server** | CLI/UI/CI 요청 처리, gRPC/REST 엔드포인트 | Stateless — 수평 확장 가능 |
| **Repository Server** | Git 클론, Helm/Kustomize 렌더링 | CPU/Memory 집약적 — 앱 수에 따라 확장 |
| **Application Controller** | Desired/Actual State 비교 및 Self-healing | 샤딩으로 수평 확장 (replicas > 1) |
| **ApplicationSet Controller** | ApplicationSet 리소스 감시 및 Application 생성 | 보통 단일 인스턴스로 충분 |
| **Dex** | OIDC SSO 연동 브로커 | 선택적 컴포넌트 |
| **Redis** | 캐시 및 컨트롤러 간 상태 공유 | HA 구성 시 Redis Sentinel/Cluster 권장 |

---

## 2. 활용법 (Usage) [보강]

### 실제 사용 패턴

1. **App-of-Apps 패턴:** 하나의 '부모' Application이 여러 '자식' Application을 관리하는 구조입니다. 대규모 인프라 구성 시 전체 서비스를 한 번에 프로비저닝할 때 유리합니다.
2. **ApplicationSet 패턴:** Generator(Git, List, Cluster 등)를 사용하여 여러 클러스터나 여러 네임스페이스에 동일한 애플리케이션을 동적으로 생성합니다. 멀티 테넌트 환경의 표준입니다.
3. **Blue/Green & Canary 배포:** Argo Rollouts와 연동하여 분석 엔진 기반의 점진적 배포 전략을 수행합니다.

### GitOps 저장소 구조 패턴 [수정: Claude]

**패턴 A — 모노레포 (Monorepo)**
```
repo/
├── apps/
│   ├── frontend/
│   └── backend/
└── infra/
    ├── base/
    └── overlays/
        ├── dev/
        ├── staging/
        └── prod/
```
- **장점:** 전체 변경 이력 단일 관리, 교차 서비스 의존성 추적 용이
- **단점:** 권한 분리 어려움, 저장소 크기 비대화

**패턴 B — 앱-인프라 분리 폴리레포 (대규모 팀 권장)**
```
app-repo/     # 개발팀 소유: 소스 코드 + CI
gitops-repo/  # 플랫폼팀 소유: K8s 매니페스트 + ArgoCD Application 정의
```
- **장점:** 팀별 책임 분리 명확, 보안 정책 격리
- **단점:** 버전 추적을 위한 이미지 태그 자동화 필요 (argocd-image-updater 활용)

### 언제 쓰고 언제 쓰지 말아야 하는지
- **언제 쓰는가:** Kubernetes 기반 MSA 운영, 멀티 클러스터 배포 관리, 인프라 변경 이력의 엄격한 관리가 필요할 때.
- **언제 쓰지 않는가:** CI(Build/Test) 단계(ArgoCD는 CD 전용), 상태값이 자주 변하는 데이터베이스 스키마 마이그레이션(별도 도구 권장), 매우 단순한 단일 노드 서비스.

---

## 3. 운영 가이드 (Operations Guide) [보강]

### 설치 및 초기 설정 (HA 구성 권장)
프로덕션 환경에서는 가용성을 위해 HA 모드로 설치해야 합니다.
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set controller.replicas=2 \
  --set server.replicas=2 \
  --set repoServer.replicas=2
```

### 프로덕션 환경 권장 설정
1. **Resource Limits:** `argocd-application-controller`에 충분한 메모리를 할당합니다. (앱 1,000개 기준 최소 4GiB 권장 [추정 — 공식 best-practice 가이드 수치 미확인])
2. **RBAC 설정:** `argocd-rbac-cm` ConfigMap을 통해 프로젝트별, 팀별 권한을 엄격히 분리합니다.
3. **Secret Management:** ArgoCD 자체는 비밀번호를 저장하지 않으므로, **HashiCorp Vault** 또는 **AWS Secrets Manager**와 연동(External Secrets Operator 등)하여 사용합니다.

### 모니터링 포인트 [수정: Claude + Codex]

| 메트릭 / 쿼리 | 용도 | 비고 |
| :--- | :--- | :--- |
| `argocd_app_info{sync_status!="Synced"}` | OutOfSync 앱 탐지 | Gauge; `sync_status` / `health_status` label 포함 |
| `argocd_app_sync_total` | 누적 Sync 시도 횟수 및 결과 | Counter; `phase` label로 성공/실패 구분 |
| `histogram_quantile(0.95, sum by (le) (rate(argocd_app_reconcile_bucket[5m])))` | Reconcile 지연시간 p95 추적 | `argocd_app_reconcile` 히스토그램 기반 |
| `argocd_cluster_connection_status` | 등록 클러스터 연결 상태 감시 | Gauge |
| `workqueue_depth` | 처리 대기 작업 수 (컨트롤러 포화 탐지) | controller-runtime 표준 메트릭; 컴포넌트별 노출 여부 확인 필요 |

> **Prometheus 예시 Alert Rule**
> ```yaml
> - alert: ArgoCDAppOutOfSync
>   expr: argocd_app_info{sync_status="OutOfSync"} == 1
>   for: 5m
>   labels:
>     severity: warning
>   annotations:
>     summary: "{{ $labels.name }} is OutOfSync"
> ```

---

## 4. 트러블슈팅 (Troubleshooting) [보강]

### 자주 발생하는 문제 Top 5

---

#### 1. OutOfSync Loop (Infinite Sync)

- **원인:** K8s Mutating Webhook이나 가변 필드(`generateName`, HPA가 관리하는 `spec.replicas`)가 Git 정의와 충돌하여 ArgoCD가 매 Reconcile마다 Sync를 재시도.
- **진단:** [수정: Claude]
  ```bash
  argocd app diff <APP_NAME>      # Git 정의 vs 클러스터 상태 차이 확인
  argocd app history <APP_NAME>   # Sync 이력으로 반복 여부 확인
  ```
- **해결책:** `spec.ignoreDifferences`로 가변 필드를 동기화 대상에서 제외하고, `RespectIgnoreDifferences=true`를 syncOptions에 추가합니다. [수정: Claude + Codex]
  ```yaml
  spec:
    ignoreDifferences:
      - group: apps
        kind: Deployment
        jsonPointers:
          - /spec/replicas        # HPA가 관리하는 replicas 제외
      - group: ""
        kind: Service
        jsonPointers:
          - /spec/clusterIP       # 자동 할당 필드 제외
    syncPolicy:
      syncOptions:
        - RespectIgnoreDifferences=true
  ```

---

#### 2. Comparison Error: context deadline exceeded

- **원인:** `repo-server`가 대용량 Helm 차트 렌더링 또는 대형 Git 저장소 클론에 과도한 시간 소요.
- **진단:** [수정: Claude]
  ```bash
  kubectl logs -n argocd deploy/argocd-repo-server --tail=100 \
    | grep -i "deadline\|timeout"
  kubectl top pod -n argocd -l app.kubernetes.io/name=argocd-repo-server
  ```
- **해결책:** [수정: Codex]
  1. `argocd-repo-server` CPU/Memory 리소스 상향 조정.
  2. `argocd-cmd-params-cm` ConfigMap에서 타임아웃 연장 (올바른 키 이름):
  ```yaml
  data:
    controller.repo.server.timeout.seconds: "180"
    server.repo.server.timeout.seconds: "180"
  # CMP sidecar 플러그인을 사용하는 경우에만 추가 검토
  # ARGOCD_EXEC_TIMEOUT=180
  ```

---

#### 3. Missing Cluster Secret (Multi-cluster)

- **원인:** 대상 클러스터 등록 시 사용된 Secret의 권한 부족 또는 네트워크 단절.
- **에러 메시지:** `rpc error: code = Unknown desc = Permission denied`
- **해결책:** `argocd cluster add` 명령 재수행 및 대상 클러스터의 `argocd-manager` ServiceAccount 권한 확인.

---

#### 4. Webhook Not Working

- **원인:** Git Provider(GitHub/GitLab)와 ArgoCD API 간의 네트워크 가시성 문제 또는 페이로드 URL 설정 오류.
- **해결책:** Ingress 설정을 확인하고 `/api/webhook` 경로가 공개되어 있는지 확인.

---

#### 5. Application Controller OOMKill [수정: Claude + Codex]

- **원인:** 단일 `application-controller` 인스턴스가 관리하는 리소스 수가 과도하여 메모리 부족 발생.
- **진단:**
  ```bash
  kubectl top pod -n argocd \
    -l app.kubernetes.io/name=argocd-application-controller
  kubectl describe pod -n argocd \
    -l app.kubernetes.io/name=argocd-application-controller \
    | grep -A5 "OOMKilled"
  ```
- **해결책:** 샤딩(Sharding)을 활성화하여 여러 컨트롤러 인스턴스로 부하 분산. Helm 또는 raw manifest 방식 중 환경에 맞게 적용합니다.

  **방법 1 — Helm (권장):**
  ```bash
  helm upgrade argocd argo/argo-cd -n argocd \
    --set controller.replicas=3
  ```

  **방법 2 — ConfigMap + StatefulSet (raw manifest 환경):**
  ```yaml
  # argocd-cmd-params-cm: 샤딩 알고리즘 설정
  # consistent-hashing은 stable 문서 기준 Alpha 기능임에 주의
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: argocd-cmd-params-cm
    namespace: argocd
  data:
    controller.sharding.algorithm: "round-robin"
  ---
  apiVersion: apps/v1
  kind: StatefulSet
  metadata:
    name: argocd-application-controller
    namespace: argocd
  spec:
    replicas: 3
    template:
      spec:
        containers:
          - name: argocd-application-controller
            env:
              - name: ARGOCD_CONTROLLER_REPLICAS
                value: "3"
  ```

  > **주의:** raw manifest 기반 배포에서는 `ARGOCD_CONTROLLER_REPLICAS` 환경 변수를 StatefulSet replicas 수와 반드시 일치시켜야 합니다. Helm 배포 환경에서는 `helm upgrade --set controller.replicas=N`이 이를 자동 처리합니다.

---

## 5. 실습 (Hands-on)

> **검증 대상 버전:** Argo CD `v3.3.0` 기준 [수정: Codex]
> **실습 환경:** Kubernetes `v1.29+`, `kubectl`, `argocd` CLI 설치 완료
> **주의:** 운영 문서에서는 `targetRevision`을 `HEAD` 대신 태그 또는 커밋 SHA로 고정하십시오. [수정: Codex]

### 실습 구성

| 트랙 | 대상 | 목표 |
| :--- | :--- | :--- |
| Track A | Argo CD 입문자 | 설치 · CLI 로그인 · 단일 앱 배포와 Sync 상태 확인 |
| Track B | 숙련된 DevOps 엔지니어 | ApplicationSet + List Generator로 멀티 네임스페이스 배포 및 환경별 값 오버라이드 검증 [수정: Claude + Codex] |

---

### 사전 준비

```bash
kubectl version --short
argocd version --client
```

예상 결과:
- `kubectl` 클라이언트가 정상 동작
- `argocd` CLI가 설치되어 있음

---

### Track A: Argo CD 설치 및 단일 앱 배포

#### Step 1. Argo CD 설치 [수정: Codex]

```bash
kubectl create namespace argocd

kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.0/manifests/install.yaml
```

#### Step 2. API Server 접속 및 로그인 [수정: Claude]

```bash
# 포트 포워딩 (로컬 접속용)
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

다른 터미널에서 초기 비밀번호를 확인합니다.

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

로그인:

```bash
argocd login localhost:8080 --username admin --password '<INITIAL_PASSWORD>' --insecure
```

#### Step 3. 단일 Application 생성

아래 내용을 `guestbook-app.yaml`로 저장 후 적용합니다.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: master
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

```bash
kubectl apply -f guestbook-app.yaml
argocd app get guestbook
kubectl get all -n guestbook
```

**예상 결과:**
- `guestbook` 네임스페이스가 자동 생성됨
- Argo CD UI/CLI에서 Application 상태가 `Synced` / `Healthy`로 표시됨
- `guestbook-ui` 관련 Deployment, Service, Pod가 생성됨

---

### Track B: ApplicationSet으로 멀티 네임스페이스 배포 [수정: Claude + Codex]

**목표:** `List Generator`를 사용해 동일 Helm 애플리케이션을 `dev`, `staging`, `prod` 네임스페이스에 배포하고, 환경별 `replicaCount` 오버라이드를 검증합니다.

#### Step 1. ApplicationSet 생성

> **중요:** 기존 `path: guestbook`은 plain YAML 예제라 `helm.parameters`가 동작하지 않습니다. 환경별 replica 오버라이드를 검증하려면 `helm-guestbook` 경로를 사용해야 합니다. [수정: Codex]

아래 내용을 `appset-multi-env.yaml`로 저장합니다.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook-multi-env
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - env: dev
            namespace: guestbook-dev
            replicas: "1"
          - env: staging
            namespace: guestbook-staging
            replicas: "2"
          - env: prod
            namespace: guestbook-prod
            replicas: "3"
  template:
    metadata:
      name: 'guestbook-{{.env}}'
      labels:
        env: '{{.env}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps.git
        targetRevision: master
        path: helm-guestbook
        helm:
          parameters:
            - name: replicaCount
              value: '{{.replicas}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{.namespace}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

```bash
kubectl apply -f appset-multi-env.yaml
```

#### Step 2. 생성된 Application 확인

```bash
argocd app list | grep guestbook
```

**예상 결과:** `guestbook-dev`, `guestbook-staging`, `guestbook-prod` 세 개의 Application이 표시됨.

#### Step 3. Sync 및 상태 검증

```bash
argocd app get guestbook-dev
argocd app get guestbook-staging
argocd app get guestbook-prod
```

**예상 결과:** 세 Application 모두 `Synced` / `Healthy`.

#### Step 4. 환경별 replicaCount 반영 여부 검증 [수정: Codex]

```bash
kubectl get deploy -n guestbook-dev guestbook-helm-guestbook \
  -o jsonpath='{.spec.replicas}{"\n"}'

kubectl get deploy -n guestbook-staging guestbook-helm-guestbook \
  -o jsonpath='{.spec.replicas}{"\n"}'

kubectl get deploy -n guestbook-prod guestbook-helm-guestbook \
  -o jsonpath='{.spec.replicas}{"\n"}'
```

**예상 결과:**
- `guestbook-dev` → `1`
- `guestbook-staging` → `2`
- `guestbook-prod` → `3`

#### Step 5. 추가 점검

```bash
kubectl get pods -n guestbook-dev
kubectl get pods -n guestbook-staging
kubectl get pods -n guestbook-prod

argocd app diff guestbook-prod
argocd app history guestbook-prod
```

---

### 실패 시 빠른 진단 [수정: Codex]

```bash
kubectl logs -n argocd deploy/argocd-applicationset-controller --tail=100
kubectl logs -n argocd statefulset/argocd-application-controller --tail=100
kubectl logs -n argocd deploy/argocd-repo-server --tail=100
```

확인 포인트:
- **템플릿 변수 누락:** `goTemplateOptions: ["missingkey=error"]`가 즉시 오류를 드러냄
- **repo 경로 오류:** `path: helm-guestbook`인지 확인
- **권한/프로젝트 제약:** `project: default`와 destination namespace 허용 범위 확인

---

### 정리 (Cleanup) [수정: Codex]

```bash
kubectl delete -f appset-multi-env.yaml
kubectl delete -f guestbook-app.yaml
kubectl delete ns guestbook guestbook-dev guestbook-staging guestbook-prod
kubectl delete ns argocd
```

---

## 6. 참고 자료 (References) [보강]

- **ArgoCD 공식 문서:** https://argo-cd.readthedocs.io/
- **ArgoCD GitHub Releases (v3.3.0):** https://github.com/argoproj/argo-cd/releases
- **Metrics 문서:** https://argo-cd.readthedocs.io/en/release-3.0/operator-manual/metrics/
- **ApplicationSet / Go Template 문서:** https://argo-cd.readthedocs.io/en/release-3.0/operator-manual/applicationset/
- **helm-guestbook 예제:** https://github.com/argoproj/argocd-example-apps/tree/master/helm-guestbook
- **GitOps 공식 가이드:** https://opengitops.dev/
- **CNCF Landscape (CD Section):** https://landscape.cncf.io/

---

## 검증 요약

| 모델 | 역할 | 주요 수정 사항 |
| :--- | :--- | :--- |
| Gemini | 초안 생성 | 6개 섹션 전체 구조 및 기초 내용 |
| Claude | 내용·구조 검증 | Rubric 총점 21/30. Critical: 메트릭명 오류(`argocd_app_sync_status` 미존재), OOMKill 설정 경로 부정확. 추가: 컴포넌트 아키텍처 표, GitOps 저장소 패턴, Track B 실습 트랙, 진단 명령어 보완 |
| Codex | 코드·실습 검증 | 코드 블록 7개 검토, 주요 오류 5건 수정. Critical: ApplicationSet `path: guestbook` → `helm-guestbook` 교체, `goTemplate: true` 누락, 대상 버전 v3.3.0 갱신, ConfigMap 타임아웃 키 이름 정정, StatefulSet 기반 샤딩 설정 보완 |
