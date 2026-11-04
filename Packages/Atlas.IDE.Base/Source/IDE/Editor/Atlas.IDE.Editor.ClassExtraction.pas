unit Atlas.IDE.Editor.ClassExtraction;

// Gemeinsamer erster Schritt von „Interface extrahieren“ (#673), „Oberklasse
// extrahieren“ (#674) und „Mitglied verschieben“ (#675): offene Puffer
// schicken, Kandidaten vom Server holen (…prepare), den Dialog „Mitglieder
// herauslösen“ zeigen und die Argumente der Code-Aktion um die Auswahl
// ergänzen. Den zweiten Schritt (WorkspaceEdit holen, Vorschau, Übernehmen)
// erledigt TAtlasIdeServerEdit.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.ClassExtraction,
  Atlas.IDE.Editor.ServerEdit;

type
  /// <summary>Titel des Dialogs (und der Vorschau) zum Modell AModel.</summary>
  TAtlasClassExtractionTitle = reference to function(AModel: TAtlasClassExtractionModel): string;

  /// <summary>Was nach dem Dialog für die Anwendung gebraucht wird.</summary>
  TAtlasClassExtractionChoice = record
    Title: string;
    /// <summary>Eingegebener Name (Interface bzw. Oberklasse), ohne Leerzeichen am Rand.</summary>
    Name: string;
    SourceClass: string;
    /// <summary>Argumente der Code-Aktion, ergänzt um die Auswahl.</summary>
    ApplyArguments: string;
  end;

  TAtlasIdeClassExtraction = class
  public
    /// <summary>APrepare liefert die Kandidaten (Arguments: Argumente der Code-Aktion); der Dialog trägt den Titel
    /// ATitle. False, wenn der Server scheitert (Meldung APrepare.Failed über AMessage) oder der Benutzer abbricht.
    /// </summary>
    class function Choose(ASession: TLspSession; const APrepare: TAtlasServerEditCommand;
      const ATitle: TAtlasClassExtractionTitle; const AMessage: TProc<string>;
      out AChoice: TAtlasClassExtractionChoice): Boolean; static;
  end;

implementation

uses
  System.JSON,
  Atlas.UI.Strings,
  Atlas.Core.Lsp.Client,
  Atlas.UI.Editor.ExtractMembers,
  Atlas.IDE.Editor.Rename;

/// <summary>Modell aus der Antwort auf APrepare; False mit Meldung, wenn der Server scheitert.</summary>
function FetchModel(ASession: TLspSession; const APrepare: TAtlasServerEditCommand; const AMessage: TProc<string>;
  out AModel: TAtlasClassExtractionModel): Boolean;
var
  mAnswer: TJSONValue;
begin
  Result := False;
  AModel := nil;
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  try
    mAnswer := ASession.RunCommand(APrepare.Command, APrepare.Arguments, APrepare.TimeoutMs);
    try
      AModel := TAtlasClassExtractionModel.Create(TAtlasIdeServerEdit.AsObject(mAnswer));
    finally
      mAnswer.Free;
    end;
    Result := True;
  except
    on E: ELspClientError do
    begin
      AMessage(TAtlasStrings.Fmt(APrepare.Failed, [E.Message]));
    end;
  end;
end;

{ TAtlasIdeClassExtraction }

class function TAtlasIdeClassExtraction.Choose(ASession: TLspSession; const APrepare: TAtlasServerEditCommand;
  const ATitle: TAtlasClassExtractionTitle; const AMessage: TProc<string>;
  out AChoice: TAtlasClassExtractionChoice): Boolean;
var
  mModel: TAtlasClassExtractionModel;
begin
  AChoice := Default(TAtlasClassExtractionChoice);
  Result := FetchModel(ASession, APrepare, AMessage, mModel);
  if not Result then
  begin
    Exit;
  end;
  try
    AChoice.Title := ATitle(mModel);
    AChoice.SourceClass := mModel.Source.SourceClass;
    Result := TAtlasExtractMembersDialog.Execute(mModel, AChoice.Title) and
      TAtlasIdeServerEdit.Appended(APrepare.Arguments, mModel.RequestJson, AChoice.ApplyArguments);
    AChoice.Name := Trim(mModel.Name);
  finally
    mModel.Free;
  end;
end;

end.
