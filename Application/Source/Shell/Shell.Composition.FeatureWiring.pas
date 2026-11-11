unit Shell.Composition.FeatureWiring;

// Verdrahtung der Features: Teilwurzeln Bearbeiten, Code, Analyse und IDE. Closures fragen die Teile
// erst beim Aufruf, weil Kern, Index und IDE in anderer Reihenfolge entstehen, als die Features sie brauchen.

interface

uses
  Shell.Composition.Parts;

type
  /// <summary>Legt die Teilwurzeln Bearbeiten, Code, Analyse und IDE in den Teilen an.</summary>
  TShellFeatureWiring = class abstract
  public
    /// <summary>Dokumentbezogene Funktionen ohne Index: Symbole, Faltung, Formatierung, Schnellbefehle.</summary>
    class procedure Editing(AParts: TShellParts); static;
    /// <summary>Teilwurzel Code nach Kern und Index.</summary>
    class procedure Code(AParts: TShellParts); static;
    /// <summary>Signaturhilfe, Hierarchien, Implementierungen, Inlay-Hints, CodeLens, Metriken, TODOs, Baseline,
    /// Semantic Tokens.</summary>
    class procedure Analysis(AParts: TShellParts); static;
    /// <summary>Anbindung an die IDE: Build-Meldungen und Projektkontext.</summary>
    class procedure Ide(AParts: TShellParts); static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.ApplyEdit,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Lsp.IdeTypes,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Pascal.FormatRoutines,
  Shell.Composition.Contract,
  Shell.Composition.Core,
  Shell.Composition.Compile,
  Shell.Composition.DiagnosticsArea,
  Shell.Composition.EditingArea,
  Shell.Composition.CodeArea,
  Shell.Composition.AnalysisArea,
  Shell.Composition.IdeArea;

class procedure TShellFeatureWiring.Editing(AParts: TShellParts);
var
  mServices: TShellEditingAreaServices;
begin
  mServices := Default(TShellEditingAreaServices);
  // Closure: Der Kern entsteht erst nach dem Bearbeiten (CoreWiring).
  mServices.Core :=
    function: TShellCore
    begin
      Result := AParts.Core;
    end;
  mServices.Editing.Documents := AParts.Documents;
  mServices.Editing.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := AParts.ReadSourceText(AFileName, AText);
    end;
  mServices.Slash.Transport := AParts.Channel.Transport;
  mServices.Slash.Logger := AParts.Channel.Logger;
  mServices.Slash.Dispatcher := AParts.Protocol.Dispatcher;
  mServices.Slash.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := AParts.ReadSourceText(AFileName, AText);
    end;
  // Die .dproj geht über das Plugin in die IDE, wenn der Client applyEdit kann (#397).
  mServices.Slash.ClientAppliesEdits :=
    function: Boolean
    begin
      Result := TLspApplyEdit.ClientSupports(AParts.Protocol.Lifecycle.InitializeParams);
    end;
  // Neu laden nur im Thread der Nachrichtenschleife; die Verbindung liest die Closure
  // erst beim Aufruf.
  mServices.Slash.RunInLoop :=
    procedure(const AWork: TProc)
    begin
      if (AParts.Connection = nil) or not AParts.Connection.Queue(AWork) then
      begin
        AParts.Channel.Logger.Warning('Schnellbefehl: Projekt nicht neu geladen, die Verbindung ist beendet');
      end;
    end;
  mServices.Slash.TestUnitContextFor :=
    function(const AUri: string; out AContext: TTestUnitContext): Boolean
    begin
      Result := AParts.TestUnitContextFor(AUri, AContext);
    end;
  mServices.Slash.UsesContextFor :=
    function(const AUri: string; out AContext: TUsesContext): Boolean
    begin
      Result := AParts.UsesContextFor(AUri, AContext);
    end;
  AParts.EditingArea := TShellEditingArea.Create(mServices);
end;

class procedure TShellFeatureWiring.Code(AParts: TShellParts);
var
  mServices: TShellCodeAreaServices;
begin
  mServices := Default(TShellCodeAreaServices);
  mServices.Logger := AParts.Channel.Logger;
  mServices.Dispatcher := AParts.Protocol.Dispatcher;
  mServices.Documents := AParts.Documents;
  mServices.Index := AParts.Index;
  mServices.EditorIndex := AParts.IndexArea.EditorIndex;
  mServices.Editing := AParts.EditingArea.Editing;
  mServices.RuleIdsFor :=
    function(const AUri, AText: string; ALine: Integer; out AIds: TArray<string>): Boolean
    begin
      Result := AParts.EditingArea.Slash.RuleIdsAt(AUri, AText, ALine, AIds);
    end;
  mServices.MessagesFor :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := AParts.Compile.Results.MessagesFor(AFileName);
    end;
  // Closure: Die Teilwurzel IDE entsteht erst nach dem Code.
  mServices.IdeProjectFor :=
    function(const AProjectFile: string; out AContext: TIdeProjectContext): Boolean
    begin
      Result := AParts.IdeArea.Ide.Project.Find(AProjectFile, AContext);
    end;
  mServices.IdeTypesFor :=
    function: TArray<TIdeTypeEntry>
    begin
      Result := AParts.IdeArea.Ide.Types.Catalog.Entries;
    end;
  mServices.VisitWorkspaces :=
    procedure(const AVisit: TShellWorkspacesProc)
    begin
      AParts.Core.Workspaces.Visit(AVisit);
    end;
  mServices.Notify :=
    procedure(const AMethod: string; AParams: TJSONObject)
    begin
      AParts.NotifyClient(AMethod, AParams);
    end;
  mServices.Log :=
    procedure(const AText: string)
    begin
      AParts.Channel.Logger.Debug(AText);
    end;
  AParts.CodeArea := TShellCodeArea.Create(AParts.Core, mServices);
end;

class procedure TShellFeatureWiring.Analysis(AParts: TShellParts);
var
  mServices: TShellAnalysisAreaServices;
begin
  mServices := Default(TShellAnalysisAreaServices);
  mServices.Logger := AParts.Channel.Logger;
  mServices.Dispatcher := AParts.Protocol.Dispatcher;
  mServices.Documents := AParts.Documents;
  mServices.Index := AParts.Index;
  mServices.EditorIndex := AParts.IndexArea.EditorIndex;
  // Closure: Die Teilwurzel IDE entsteht erst nach der Analyse.
  mServices.FormatRoutinesFor :=
    function(const AUri: string): TArray<TFormatRoutine>
    begin
      Result := AParts.IdeArea.FormatRoutinesFor(AUri);
    end;
  mServices.UsesContextFor :=
    function(const AUri: string; out AContext: TUsesContext): Boolean
    begin
      Result := AParts.UsesContextFor(AUri, AContext);
    end;
  mServices.RefreshLater :=
    procedure
    begin
      AParts.DiagnosticsArea.Syntax.RefreshLater;
    end;
  mServices.TestUnitContext :=
    function(const AUri: string; out AContext: TTestUnitContext): Boolean
    begin
      Result := AParts.TestUnitContextFor(AUri, AContext);
    end;
  mServices.RequestTimeout :=
    function: Cardinal
    begin
      Result := AParts.CurrentRequestTimeout;
    end;
  AParts.AnalysisArea := TShellAnalysisArea.Create(AParts.Core, mServices);
end;

class procedure TShellFeatureWiring.Ide(AParts: TShellParts);
var
  mServices: TShellIdeAreaServices;
begin
  mServices.Logger := AParts.Channel.Logger;
  mServices.Transport := AParts.Channel.Transport;
  mServices.Dispatcher := AParts.Protocol.Dispatcher;
  // Beim Beenden sind Diagnosen und Compile-Host vor der Teilwurzel IDE fort.
  mServices.Diagnostics :=
    function: TShellDiagnosticsArea
    begin
      Result := AParts.DiagnosticsArea;
    end;
  mServices.Compile :=
    function: TShellCompileHost
    begin
      Result := AParts.Compile;
    end;
  mServices.IdeUnits := AParts.IndexArea.IdeUnits;
  mServices.Index := AParts.Index;
  AParts.IdeArea := TShellIdeArea.Create(AParts.Core, mServices);
end;

end.
