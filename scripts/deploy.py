#!/usr/bin/env python3
"""
UnityExpress Deployment CLI
Production-grade deployment automation using Click framework
"""

import os
import sys
import subprocess
import platform
from pathlib import Path
from typing import Optional, List
from dataclasses import dataclass

import click
from rich.console import Console
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.panel import Panel

# Initialize Rich console for beautiful output
console = Console()

# ============================================================
# Configuration
# ============================================================

PROJECT_UUID = "e271b052-9200-4502-b491-62f1649c07"
NAMESPACE = "unityexpress"
MONITORING_NAMESPACE = "monitoring"

@dataclass
class DeploymentConfig:
    """Deployment configuration"""
    project_root: Path
    chart_path: Path
    monitoring_values: Path
    api_image: str = "unityexpress-api:local"
    web_image: str = "unityexpress-web:local"
    
    @classmethod
    def from_project_root(cls, root: Path) -> 'DeploymentConfig':
        return cls(
            project_root=root,
            chart_path=root / "charts" / "unityexpress",
            monitoring_values=root / "monitoring" / "prometheus-adapter-values.yaml"
        )


# ============================================================
# Utility Functions
# ============================================================

def find_project_root(start: Optional[Path] = None) -> Path:
    """
    Recursively search for project root directory.
    
    Args:
        start: Starting directory (defaults to script location)
        
    Returns:
        Path to project root
        
    Raises:
        click.ClickException: If project root not found
    """
    current = start or Path(__file__).resolve().parent
    
    while True:
        required_dirs = ["api-server", "charts", "monitoring", "scripts"]
        if all((current / d).is_dir() for d in required_dirs):
            return current
        
        parent = current.parent
        if parent == current:
            raise click.ClickException(
                "Could not locate UnityExpress project root. "
                "Ensure you're running from within the project directory."
            )
        current = parent


def run_command(
    cmd: str,
    check: bool = True,
    capture: bool = False,
    quiet: bool = False
) -> Optional[str]:
    """
    Execute shell command with proper error handling.
    
    Args:
        cmd: Command to execute
        check: Raise exception on failure
        capture: Return command output
        quiet: Suppress command echo
        
    Returns:
        Command output if capture=True, None otherwise
        
    Raises:
        click.ClickException: If command fails and check=True
    """
    if not quiet:
        console.print(f"[dim]$ {cmd}[/dim]")
    
    try:
        if capture:
            return subprocess.check_output(
                cmd, 
                shell=True, 
                text=True,
                stderr=subprocess.STDOUT
            ).strip()
        
        result = subprocess.run(cmd, shell=True)
        if check and result.returncode != 0:
            raise click.ClickException(f"Command failed: {cmd}")
        return None
        
    except subprocess.CalledProcessError as e:
        if check:
            raise click.ClickException(f"Command failed: {cmd}\n{e.output}")
        return None


def detect_platform() -> str:
    """Detect operating system platform"""
    system = platform.system().lower()
    if "darwin" in system:
        return "mac"
    elif "windows" in system:
        return "windows"
    return "linux"


def check_prerequisites() -> List[str]:
    """
    Check if required tools are installed.
    
    Returns:
        List of missing tools
    """
    required_tools = ["minikube", "kubectl", "helm", "docker"]
    missing = []
    
    for tool in required_tools:
        try:
            run_command(f"{tool} version", capture=True, quiet=True)
        except:
            missing.append(tool)
    
    return missing


def configure_docker_env():
    """Configure Docker to use Minikube's daemon"""
    try:
        output = run_command("minikube docker-env --shell bash", capture=True, quiet=True)
        for line in output.splitlines():
            if "export" in line:
                key, val = line.replace("export ", "").split("=", 1)
                os.environ[key] = val.strip('"')
    except Exception as e:
        console.print(f"[yellow]Warning: Could not configure Docker env: {e}[/yellow]")


# ============================================================
# Deployment Steps
# ============================================================

def validate_environment(config: DeploymentConfig):
    """Validate deployment environment"""
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console
    ) as progress:
        task = progress.add_task("Validating environment...", total=None)
        
        # Check prerequisites
        missing = check_prerequisites()
        if missing:
            raise click.ClickException(
                f"Missing required tools: {', '.join(missing)}\n"
                "Please install them before proceeding."
            )
        
        # Check Minikube status
        try:
            run_command("minikube status", quiet=True)
        except:
            raise click.ClickException(
                "Minikube is not running. Start it with: minikube start"
            )
        
        # Verify monitoring config exists
        if not config.monitoring_values.exists():
            raise click.ClickException(
                f"Missing monitoring config: {config.monitoring_values}"
            )
        
        progress.update(task, completed=True)
    
    console.print("[green]✓[/green] Environment validation passed")


def install_monitoring(skip_if_exists: bool = False):
    """Install Prometheus monitoring stack"""
    console.print("\n[bold cyan]Installing Monitoring Stack[/bold cyan]")
    
    if skip_if_exists:
        try:
            run_command(
                f"helm status monitoring -n {MONITORING_NAMESPACE}",
                capture=True,
                quiet=True
            )
            console.print("[yellow]Monitoring already installed, skipping[/yellow]")
            return
        except:
            pass
    
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console
    ) as progress:
        task = progress.add_task("Installing monitoring...", total=3)
        
        # Add repo
        run_command(
            "helm repo add prometheus-community "
            "https://prometheus-community.github.io/helm-charts",
            quiet=True
        )
        progress.advance(task)
        
        # Update repo
        run_command("helm repo update", quiet=True)
        progress.advance(task)
        
        # Install stack
        run_command(
            f"helm upgrade --install monitoring "
            f"prometheus-community/kube-prometheus-stack "
            f"-n {MONITORING_NAMESPACE} --create-namespace --wait",
            quiet=True
        )
        progress.advance(task)
    
    console.print("[green]✓[/green] Monitoring stack installed")


def build_images(config: DeploymentConfig, no_cache: bool = False):
    """Build Docker images"""
    console.print("\n[bold cyan]Building Docker Images[/bold cyan]")
    
    # Configure Docker to use Minikube
    configure_docker_env()
    
    cache_flag = "--no-cache" if no_cache else ""
    
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console
    ) as progress:
        task = progress.add_task("Building images...", total=2)
        
        # Build API
        run_command(
            f"docker build {cache_flag} -t {config.api_image} "
            f"{config.project_root / 'api-server'}",
            quiet=True
        )
        progress.advance(task)
        
        # Build Web
        run_command(
            f"docker build {cache_flag} -t {config.web_image} "
            f"{config.project_root / 'web-server'}",
            quiet=True
        )
        progress.advance(task)
    
    console.print("[green]✓[/green] Images built successfully")


def deploy_application(config: DeploymentConfig, dry_run: bool = False):
    """Deploy UnityExpress application"""
    console.print("\n[bold cyan]Deploying UnityExpress[/bold cyan]")
    
    dry_run_flag = "--dry-run" if dry_run else ""
    
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console
    ) as progress:
        task = progress.add_task("Deploying application...", total=None)
        
        run_command(
            f"helm upgrade --install unityexpress {config.chart_path} "
            f"-n {NAMESPACE} --create-namespace "
            f"--set projectUuid={PROJECT_UUID} {dry_run_flag}",
            quiet=True
        )
        
        if not dry_run:
            # Wait for deployments
            run_command(
                f"kubectl wait --for=condition=Available "
                f"deployment/unityexpress-api -n {NAMESPACE} --timeout=120s",
                check=False,
                quiet=True
            )
        
        progress.update(task, completed=True)
    
    console.print("[green]✓[/green] Application deployed")


def show_status():
    """Display deployment status"""
    console.print("\n[bold cyan]Deployment Status[/bold cyan]\n")
    
    # Get pods
    pods_output = run_command(
        f"kubectl get pods -n {NAMESPACE} --no-headers",
        capture=True
    )
    
    # Create table
    table = Table(show_header=True, header_style="bold magenta")
    table.add_column("Pod", style="cyan")
    table.add_column("Status", style="green")
    table.add_column("Restarts")
    table.add_column("Age")
    
    for line in pods_output.splitlines():
        parts = line.split()
        if len(parts) >= 5:
            name, ready, status, restarts, age = parts[:5]
            status_color = "green" if "Running" in status else "yellow"
            table.add_row(name, f"[{status_color}]{status}[/{status_color}]", restarts, age)
    
    console.print(table)


def get_service_urls() -> dict:
    """Get service URLs"""
    urls = {}
    
    try:
        gateway_url = run_command(
            f"minikube service unityexpress-gateway -n {NAMESPACE} --url",
            capture=True,
            quiet=True
        )
        urls["Gateway"] = gateway_url.splitlines()[0] if gateway_url else "N/A"
    except:
        urls["Gateway"] = "N/A"
    
    try:
        api_url = run_command(
            f"minikube service unityexpress-api -n {NAMESPACE} --url",
            capture=True,
            quiet=True
        )
        urls["API"] = api_url.splitlines()[0] if api_url else "N/A"
    except:
        urls["API"] = "N/A"
    
    return urls


# ============================================================
# CLI Commands
# ============================================================

@click.group()
@click.version_option(version="1.0.0", prog_name="UnityExpress Deploy")
def cli():
    """
    UnityExpress Deployment CLI
    
    Production-grade deployment automation for Kubernetes
    """
    pass


@cli.command()
@click.option(
    '--skip-monitoring',
    is_flag=True,
    help='Skip monitoring stack installation'
)
@click.option(
    '--no-cache',
    is_flag=True,
    help='Build images without cache'
)
@click.option(
    '--dry-run',
    is_flag=True,
    help='Simulate deployment without applying changes'
)
def deploy(skip_monitoring: bool, no_cache: bool, dry_run: bool):
    """Deploy UnityExpress to Minikube"""
    
    console.print(Panel.fit(
        f"[bold cyan]UnityExpress Deployment[/bold cyan]\n"
        f"Project UUID: [yellow]{PROJECT_UUID}[/yellow]",
        border_style="cyan"
    ))
    
    try:
        # Find project root
        project_root = find_project_root()
        config = DeploymentConfig.from_project_root(project_root)
        console.print(f"[dim]Project root: {config.project_root}[/dim]\n")
        
        # Validate environment
        validate_environment(config)
        
        # Install monitoring
        if not skip_monitoring:
            install_monitoring(skip_if_exists=True)
        
        # Build images
        build_images(config, no_cache=no_cache)
        
        # Deploy application
        deploy_application(config, dry_run=dry_run)
        
        if not dry_run:
            # Show status
            show_status()
            
            # Get URLs
            urls = get_service_urls()
            
            console.print("\n[bold green]Deployment Complete![/bold green]\n")
            console.print(f"Gateway URL: [cyan]{urls.get('Gateway', 'N/A')}[/cyan]")
            console.print(f"API URL:     [cyan]{urls.get('API', 'N/A')}[/cyan]")
            console.print(f"\nProject UUID: [yellow]{PROJECT_UUID}[/yellow]")
        
    except click.ClickException as e:
        console.print(f"\n[bold red]Error:[/bold red] {e.message}")
        sys.exit(1)
    except Exception as e:
        console.print(f"\n[bold red]Unexpected error:[/bold red] {e}")
        sys.exit(1)


@cli.command()
def status():
    """Show deployment status"""
    try:
        show_status()
        
        urls = get_service_urls()
        console.print("\n[bold cyan]Service URLs[/bold cyan]")
        console.print(f"Gateway: [cyan]{urls.get('Gateway', 'N/A')}[/cyan]")
        console.print(f"API:     [cyan]{urls.get('API', 'N/A')}[/cyan]")
        
    except Exception as e:
        console.print(f"[bold red]Error:[/bold red] {e}")
        sys.exit(1)


@cli.command()
@click.confirmation_option(prompt="Are you sure you want to destroy the deployment?")
def destroy():
    """Destroy UnityExpress deployment"""
    console.print("[bold red]Destroying deployment...[/bold red]")
    
    try:
        run_command(f"helm uninstall unityexpress -n {NAMESPACE}", check=False)
        run_command(f"kubectl delete namespace {NAMESPACE} --ignore-not-found=true")
        
        console.print("[green]✓[/green] Deployment destroyed")
        
    except Exception as e:
        console.print(f"[bold red]Error:[/bold red] {e}")
        sys.exit(1)


@cli.command()
def logs():
    """Show application logs"""
    console.print("[bold cyan]Application Logs[/bold cyan]\n")
    
    try:
        run_command(f"kubectl logs -n {NAMESPACE} deploy/unityexpress-api --tail=50")
    except:
        console.print("[yellow]Could not retrieve logs[/yellow]")


@cli.command()
def open_ui():
    """Open UI in browser"""
    try:
        run_command(f"minikube service unityexpress-gateway -n {NAMESPACE}")
    except Exception as e:
        console.print(f"[bold red]Error:[/bold red] {e}")
        sys.exit(1)


@cli.command()
def validate():
    """Validate deployment environment"""
    try:
        project_root = find_project_root()
        config = DeploymentConfig.from_project_root(project_root)
        validate_environment(config)
        
        console.print("\n[bold green]✓ Environment is ready for deployment[/bold green]")
        
    except click.ClickException as e:
        console.print(f"\n[bold red]Validation failed:[/bold red] {e.message}")
        sys.exit(1)


if __name__ == "__main__":
    cli()