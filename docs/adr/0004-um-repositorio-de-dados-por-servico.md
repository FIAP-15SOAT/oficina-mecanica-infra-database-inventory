# ADR 0004: Um repositório de dados por serviço

## Status

Aceito — 2026-10-23

## Contexto

Na Fase 3, a solução tinha uma única API (`oficina-mecanica-api`) e um único repositório Terraform de banco (`oficina-mecanica-infra-database`), que provisionava a instância RDS `rds-oficina-mecanica` com state em `infra/prod-simulated/database/terraform.tfstate` e Security Group aberto para toda a CIDR da VPC.

Na Fase 4, a solução foi dividida em quatro microsserviços independentes (Ordem de Serviço, `identity`, `billing` e `inventory`), cada um dono exclusivo do próprio banco relacional PostgreSQL e do próprio cache NoSQL (ElastiCache for Valkey), sem banco compartilhado e sem acesso cruzado a credenciais ou conexões de outro contexto. Era necessário definir:

1. como organizar os repositórios e os states Terraform de dados dos quatro serviços;
2. como parametrizar a configuração para que os quatro repositórios mantenham o mesmo desenho sem duplicação ad-hoc;
3. como restringir o acesso de rede no nível de Security Group exclusivamente aos nós do cluster EKS.

## Decisão

1. **Um repositório de dados por serviço (`oficina-mecanica-infra-database-<contexto>`)**:
   - Criar o repositório `oficina-mecanica-infra-database-inventory` seguindo o template padronizado dos repositórios de dados da Fase 4.
   - Provisionar neste repositório exclusivamente os recursos de dados do contexto `inventory` — o RDS PostgreSQL 18 (`rds-oficina-mecanica-inventory`), o ElastiCache for Valkey 9.1 (`cache-oficina-mecanica-inventory`), os subnet groups, os Security Groups e os secrets dos dois — com state próprio em `infra/prod-simulated/infra-database-inventory/terraform.tfstate`.

2. **`service_context` como única variável de contexto**:
   - Declarar `variable "service_context"` em `terraform/variables.tf` com `default = "inventory"` e derivar em `terraform/locals.tf` todos os nomes e identificadores fixos:
     - `rds-${var.project_name}-${var.service_context}` (`rds-oficina-mecanica-inventory`)
     - `dbsng-${var.project_name}-${var.service_context}` (`dbsng-oficina-mecanica-inventory`)
     - `secgrp-rds-${var.project_name}-${var.service_context}` (`secgrp-rds-oficina-mecanica-inventory`)
     - `cache-${var.project_name}-${var.service_context}` (`cache-oficina-mecanica-inventory`)
     - `cachesng-${var.project_name}-${var.service_context}` (`cachesng-oficina-mecanica-inventory`)
     - `secgrp-cache-${var.project_name}-${var.service_context}` (`secgrp-cache-oficina-mecanica-inventory`)
     - `cache-${var.project_name}-${var.service_context}-auth-token` (`cache-oficina-mecanica-inventory-auth-token`)

3. **Security Groups restritos ao Security Group de identidade dos nós do EKS**:
   - Declarar as regras de entrada inline nos próprios `aws_security_group` deste repositório (`secgrp_rds` na porta `5432` e `secgrp_cache` na porta `6379`) aceitando tráfego exclusivamente a partir de `eks_nodes_security_group_id` (`secgrp-eks-nodes-oficina-mecanica`), lido do remote state do `oficina-mecanica-infra-base`, sem regras por CIDR e sem regras de saída (`egress`).
   - Este repositório **não** possui regras de entrada por CIDR de sub-rede privada nem data source de sub-rede, pois a Lambda `customer-auth` nunca acessa o banco de `inventory` diretamente.

4. **Outputs escalares estáveis**:
   - Exportar os 9 outputs `db_*` (`db_instance_id`, `db_instance_arn`, `db_endpoint`, `db_host`, `db_address`, `db_port`, `db_name`, `db_security_group_id`, `db_credentials_secret_arn`) e os 4 outputs escalares do cache (`cache_primary_endpoint`, `cache_port`, `cache_auth_token_secret_name`, `cache_security_group_id`), sem expor senha, token ou URL de conexão.

## Alternativas consideradas

- **Um único repositório `oficina-mecanica-infra-database` com `for_each` para os 4 serviços**: concentraria o ciclo de vida, o blast radius e o lock do state de todos os bancos e caches num único pipeline, contrariando a exigência de infraestrutura e persistência isoladas por microsserviço (AD-15, §18.2).
- **Um repositório para todos os RDS e outro para todos os ElastiCache**: separaria por tecnologia em vez de por bounded context, exigindo dois pipelines e dois states para subir ou recriar os dados de um único serviço.
- **Módulo Terraform compartilhado e versionado entre os 4 repositórios de dados**: introduziria sobrecarga de versionamento e publicação de módulo para quatro stacks pequenas de 9 arquivos; manter `service_context` em `variables.tf` e copiar o template com checklist no PR é mais simples e direto.
- **Ler o Security Group do cluster no state do `oficina-mecanica-infra-k8s`**: impediria que os 4 repositórios de dados subissem em paralelo com o `infra-k8s` na camada 2 de provisionamento; usar o `eks_nodes_security_group_id` exportado pelo `infra-base` permite o paralelismo.

## Consequências

- **Positivas**:
  - Isolamento completo de state, pipeline e credenciais para o contexto `inventory`.
  - Os 4 repositórios de dados sobem e são destruídos em paralelo logo após o `infra-base`, sem esperar o cluster EKS.
  - O CD do `oficina-mecanica-inventory-service` descobre apenas o RDS (`rds-oficina-mecanica-inventory`) e o ElastiCache (`cache-oficina-mecanica-inventory`) do próprio contexto pelos identificadores fixos.
  - Nenhum recurso na VPC fora dos nós do EKS alcança o RDS ou o ElastiCache deste contexto.
- **Negativas / Trade-offs**:
  - Mudanças estruturais nos arquivos Terraform precisam ser replicadas nos 4 repositórios de dados, mitigado pelo uso de `service_context` como única variável que muda entre eles.

## Revisar se

- O número de repositórios de dados crescer além dos 4 contextos atuais e a manutenção das cópias justificar a extração de um módulo Terraform versionado.
