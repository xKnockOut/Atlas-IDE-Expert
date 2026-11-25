unit Atlas.Common.Editing.Providers.SlashCommands;

// IEditingSlashChecks über das gemeinsame Register der Schnellbefehle und die Texte der Pflegebefehle.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.Contract.SlashCommands;

type
  TEditingSlashChecksProvider = class(TInterfacedObject, IEditingSlashChecks)
  public
    function Problems(const AText: string; const AIndex: ISymbolIndex;
      const ADelphiVersion: string): TArray<TSlashProblem>;
    function IgnoreWithoutHit(const ARuleId: string): string;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.MaintenanceCommands;

{ TEditingSlashChecksProvider }

function TEditingSlashChecksProvider.Problems(const AText: string; const AIndex: ISymbolIndex;
  const ADelphiVersion: string): TArray<TSlashProblem>;
begin
  Result := TSlashCommandRegistry.Shared.Problems(AText, nil, AIndex, ADelphiVersion);
end;

function TEditingSlashChecksProvider.IgnoreWithoutHit(const ARuleId: string): string;
begin
  Result := Format(IgnoreNoHitHint, [ARuleId]);
end;

end.
