unit Atlas.IDE.Assistants.Instructions;

// Anweisungsdateien für KI-Assistenten im Modul KI-Assistenten (#2615): Befehl „Anweisungen für KI-Assistenten
// aktualisieren“ (Atlas-Menü und Befehlspalette) lässt den Server den Abschnitt aus atlas.json in jede Datei aus
// assistants.instructions.file schreiben und zeigt danach je Datei den Vergleich alt/neu in der Meldungsansicht.
// Nach dem Speichern einer atlas.json fragt das Modul den Stand ab und weist auf veraltete Abschnitte hin
// (assistants.instructionsHint). Serverbefehle nur über TAtlasIdeHost, Antworten nur, solange der Scope des Moduls
// offen ist (Regel 3).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasModuleScopeFunc = reference to function: IAtlasModuleScope;

  TAtlasIdeInstructions = class(TInterfacedObject, IAtlasCommandSource, IAtlasMenuSource, IAtlasFollowsSaves)
  public const
    cCommandId = 'atlas.assistants.updateInstructions';
    cTimeoutMs = 30000;
  private
    FScope: TAtlasModuleScopeFunc;
    /// <summary>Server fragen bzw. schreiben lassen; AWrite: Abschnitte schreiben und den Vergleich melden, sonst
    /// nur veraltete Abschnitte melden.</summary>
    procedure Run(const AUri: string; AWrite: Boolean);
  public
    /// <summary>AScope liefert den Scope des Moduls (nil nach dem Abmelden).</summary>
    constructor Create(const AScope: TAtlasModuleScopeFunc);
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    procedure FileSaved(const AFileName: string);
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Uris,
  Atlas.Core.Assistants.Instructions,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Assistants.Strings;

/// <summary>Meldet eine Datei nach dem Schreiben: geschrieben mit Vergleich, aktuell oder Fehler.</summary>
procedure ReportWritten(const AFile: TAtlasInstructionsFile);
var
  mLine: string;
begin
  if AFile.Error <> '' then
  begin
    TAtlasIdeHost.Message(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.InstructionsFailed,
      [AFile.FileName, AFile.Error]));
  end
  else if AFile.Written then
  begin
    TAtlasIdeHost.Message(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.InstructionsWritten, [AFile.FileName]));
    for mLine in TAtlasInstructions.Diff(AFile.OldSection, AFile.NewSection) do
    begin
      TAtlasIdeHost.Message('  ' + mLine);
    end;
  end
  else
  begin
    TAtlasIdeHost.Message(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.InstructionsCurrent, [AFile.FileName]));
  end;
end;

/// <summary>Antwort des Servers melden. Eigene Routine, damit die anonyme Methode nur AWrite einfängt.</summary>
function AnswerHandler(AWrite: Boolean): TProc<string>;
begin
  Result :=
    procedure(AText: string)
    var
      mAnswer: TJSONValue;
      mFiles: TArray<TAtlasInstructionsFile>;
      mFile: TAtlasInstructionsFile;
    begin
      mAnswer := nil;
      if AText <> '' then
      begin
        mAnswer := TJSONValue.ParseJSONValue(AText);
      end;
      try
        mFiles := TAtlasInstructions.Parse(mAnswer);
      finally
        mAnswer.Free;
      end;
      if AWrite and (AText = '') then
      begin
        TAtlasIdeHost.Message(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.InstructionsNoAnswer));
      end
      else if AWrite and (mFiles = nil) then
      begin
        TAtlasIdeHost.Message(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.InstructionsNoFiles));
      end;
      for mFile in mFiles do
      begin
        if AWrite then
        begin
          ReportWritten(mFile);
        end
        else if mFile.Outdated then
        begin
          TAtlasIdeHost.Message(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.InstructionsStale,
            [mFile.FileName]));
        end;
      end;
    end;
end;

{ TAtlasIdeInstructions }

constructor TAtlasIdeInstructions.Create(const AScope: TAtlasModuleScopeFunc);
begin
  inherited Create;
  FScope := AScope;
end;

procedure TAtlasIdeInstructions.Run(const AUri: string; AWrite: Boolean);
var
  mScope: IAtlasModuleScope;
begin
  mScope := FScope();
  if mScope = nil then
  begin
    Exit;
  end;
  // Schreiben startet den Server bei Bedarf; der Hinweis nach dem Speichern fragt nur einen laufenden.
  if not AWrite and (TAtlasIdeHost.ActiveSession = nil) then
  begin
    Exit;
  end;
  if not TAtlasIdeHost.RunServerCommandAsync(mScope, TAtlasFeature.Server, TAtlasInstructions.cCommand,
    TAtlasInstructions.Arguments(AUri, AWrite), cTimeoutMs, AnswerHandler(AWrite)) and AWrite then
  begin
    TAtlasIdeHost.Message(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.InstructionsNoAnswer));
  end;
end;

/// <summary>Aktion des Befehls: schreiben lassen, gesichert über den Wächter. Eigene Routine, damit die anonymen
/// Methoden nur AInstructions einfangen.</summary>
function WriteAction(AInstructions: TAtlasIdeInstructions): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Server,
        procedure
        begin
          AInstructions.Run('', True);
        end);
    end;
end;

function TAtlasIdeInstructions.Commands: TArray<TAtlasModuleCommand>;
var
  mCommand: TAtlasModuleCommand;
begin
  mCommand := Default(TAtlasModuleCommand);
  mCommand.Id := cCommandId;
  mCommand.Caption := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.InstructionsCommand);
  mCommand.Run := WriteAction(Self);
  Result := [mCommand];
end;

function TAtlasIdeInstructions.MenuEntries: TArray<TAtlasMenuEntry>;
var
  mEntry: TAtlasMenuEntry;
begin
  mEntry := Default(TAtlasMenuEntry);
  mEntry.CommandId := cCommandId;
  mEntry.Place := TAtlasMenuPlace.AtlasMenu;
  Result := [mEntry];
end;

procedure TAtlasIdeInstructions.FileSaved(const AFileName: string);
begin
  if TAtlasIdeSettings.Current.AssistantsInstructionsHint and TAtlasInstructions.IsConfigFile(AFileName) then
  begin
    Run(TLspUris.FromPath(AFileName), False);
  end;
end;

end.
