using System;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.CommandPalette.Extensions;

namespace GoClaudeExtension;

[Guid("8D56FE51-EBF4-40DE-94F3-29779EAA1F45")]
public sealed partial class GoClaudeExtension : IExtension, IDisposable
{
    private readonly ManualResetEvent _extensionDisposedEvent;
    private readonly GoClaudeCommandsProvider _provider = new();

    public GoClaudeExtension(ManualResetEvent extensionDisposedEvent)
    {
        _extensionDisposedEvent = extensionDisposedEvent;
    }

    public object? GetProvider(ProviderType providerType)
    {
        return providerType switch
        {
            ProviderType.Commands => _provider,
            _ => null,
        };
    }

    public void Dispose() => _extensionDisposedEvent.Set();
}
