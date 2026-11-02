variable "subscription_id" {
  type        = string
  description = "Explicit target subscription UUID; never inferred from CLI defaults."
  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "Provide a subscription UUID."
  }
}

variable "location" {
  type    = string
  default = "polandcentral"
}

variable "prefix" {
  type    = string
  default = "devopslab"
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,11}$", var.prefix))
    error_message = "Use 3-12 lowercase letters/digits, starting with a letter."
  }
}

variable "suffix" {
  type        = string
  description = "Unique 4-8 lowercase letters/digits for globally unique ACR naming."
  validation {
    condition     = can(regex("^[a-z0-9]{4,8}$", var.suffix))
    error_message = "Use 4-8 lowercase letters/digits."
  }
}

variable "operator_object_id" {
  type        = string
  description = "Entra object ID of the human operating this lab (not application/client ID)."
  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.operator_object_id))
    error_message = "Provide the operator's Entra object UUID."
  }
}

variable "operator_cidr" {
  type        = string
  description = "Your current public IPv4 /32, allowed to reach the Kubernetes API."
  validation {
    condition     = can(cidrhost(var.operator_cidr, 0)) && endswith(var.operator_cidr, "/32")
    error_message = "Provide a valid public IPv4 /32 CIDR."
  }
}

variable "node_size" {
  type    = string
  default = "Standard_D4as_v5"
}

variable "kubernetes_version" {
  type        = string
  description = "Select a supported regional version from az aks get-versions before apply."
}
