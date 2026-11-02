import jenkins.model.Jenkins
import hudson.model.ParametersDefinitionProperty
import hudson.model.StringParameterDefinition
import hudson.plugins.git.GitSCM
import hudson.plugins.git.BranchSpec
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition

def instance = Jenkins.get()
def revision = System.getenv('LAB_SOURCE_REF')
if (!(revision ==~ /[0-9a-f]{40}/)) {
    throw new IllegalArgumentException('LAB_SOURCE_REF must be an exact commit SHA')
}
def job = instance.getItem('lab-verify')
if (job == null) {
    job = instance.createProject(WorkflowJob, 'lab-verify')
}
def source = new GitSCM('https://github.com/JeanneBM/devops-platform-lab-azure.git')
source.setBranches([new BranchSpec(revision)])
def definition = new CpsScmFlowDefinition(source, 'Jenkinsfile')
definition.setLightweight(true)
job.setDefinition(definition)
job.addProperty(new ParametersDefinitionProperty(
    new StringParameterDefinition('SOURCE_REF', revision, 'Shared library commit (same revision as pipeline by default)')))
job.setDescription('Test Python and Java on a disposable Kubernetes pod; load the repo shared library.')
job.save()
println('Lab job configured at commit ' + revision)
