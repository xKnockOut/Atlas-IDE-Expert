unit Atlas.IDE.Completion.EditorSnippets;

// Vervollständigung im Editor (#410), Stufe Code-Vorlagen (#51): mitgelieferte, Live Templates der IDE
// (abschaltbar, ImportIdeTemplates), eigene aus %APPDATA%\Atlas\Snippets und die des Projekts aus der Projektdatei
// .atlas (#486); neu gelesen, wenn sich ein Ordner ändert. Eigene Postfix-Vorlagen (#188) gehen an den Server.
// Kette: Atlas.IDE.Completion.EditorState.

interface

uses
  Atlas.Core.Completion.Snippets,
  Atlas.IDE.Completion.EditorState;

type
  TAtlasEditorCompletionSnippets = class(TAtlasEditorCompletionState)
  protected
    /// <summary>Eigene Vorlagen neu lesen, wenn sich der Ordner geändert hat (höchstens alle 3 s).</summary>
    procedure RefreshSnippets;
    /// <summary>Eigene Postfix-Vorlagen (#188) an den Server schicken (atlas/postfixTemplates).</summary>
    procedure SendPostfixTemplates;
  public
    /// <summary>Ordner der eigenen Code-Vorlagen (#51): %APPDATA%\Atlas\Snippets.</summary>
    class function SnippetFolder: string; static;
    /// <summary>Live Templates der laufenden IDE (#51); '' ohne Version.</summary>
    class function IdeTemplateFolder: string; static;
    /// <summary>Alle Code-Vorlagen (mitgeliefert, Live Templates der IDE, eigene) für das Erzeugen-Menü (#719);
    /// leer, wenn Code-Vorlagen aus sind (completion.snippets).</summary>
    function Snippets: TAtlasSnippetList;
    /// <summary>Eigene Dateivorlagen (#759) aus dem Ordner der Code-Vorlagen; leer, wenn Code-Vorlagen aus sind.
    /// </summary>
    function FileSnippets: TAtlasSnippetList;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  ToolsAPI,
  Atlas.Core.Completion.LiveTemplates,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Projects.Contract,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.TeamFile;

const
  /// <summary>Kürzester Abstand zwischen zwei Blicken in die Vorlagenordner.</summary>
  cSnippetCheckMs = 3000;
  /// <summary>Postfix-Vorlagen spätestens nach einer Minute erneut an denselben Server.</summary>
  cPostfixResendMs = 60000;

{ TAtlasEditorCompletionSnippets }

procedure TAtlasEditorCompletionSnippets.RefreshSnippets;
var
  mFolder, mIdeFolder, mTeamFolder, mStamp: string;
  mErrors, mTeamErrors: TArray<string>;
  mOwn, mIde, mTeam: TAtlasSnippetList;
  mStats: TAtlasLiveTemplateStats;
begin
  if (FSnippets.Checked <> 0) and (TThread.GetTickCount64 - FSnippets.Checked < cSnippetCheckMs) then
  begin
    Exit;
  end;
  FSnippets.Checked := TThread.GetTickCount64;
  mFolder := SnippetFolder;
  mIdeFolder := '';
  if TAtlasIdeSettings.Current.ImportIdeTemplates then
  begin
    mIdeFolder := IdeTemplateFolder;
  end;
  // Vorlagen des Projekts aus der Projektdatei .atlas (#486): gelten für alle im Team, vor den eigenen.
  mTeamFolder := TAtlasIdeTeamFile.Current.SnippetFolder;
  mStamp := TAtlasSnippets.FolderStamp(mFolder) + '#' + TAtlasLiveTemplates.FolderStamp(mIdeFolder) + '#' +
    mTeamFolder + '#' + TAtlasSnippets.FolderStamp(mTeamFolder);
  if mStamp = FSnippets.Stamp then
  begin
    Exit;
  end;
  FSnippets.Stamp := mStamp;
  mOwn := TAtlasSnippets.LoadFolder(mFolder, mErrors);
  mTeam := TAtlasSnippets.LoadFolder(mTeamFolder, mTeamErrors);
  mOwn := TAtlasSnippets.Merge(mOwn, mTeam);
  // Postfix-Vorlagen (#188) bietet der Server hinter Ausdrücken an, nicht die Liste am Anweisungsanfang.
  FSnippets.Postfix := TAtlasSnippets.Postfixes(mOwn);
  FSnippets.PostfixSession := nil;
  mOwn := TAtlasSnippets.WithoutPostfix(mOwn);
  // Dateivorlagen (#759) legen eine ganze Datei an; „Neu mit Atlas“ holt sie über FileSnippets.
  FSnippets.Files := TAtlasSnippets.FileTemplates(mOwn);
  mOwn := TAtlasSnippets.WithoutFileTemplates(mOwn);
  mIde := TAtlasLiveTemplates.LoadFolder(mIdeFolder, mStats);
  // Ohne Datei- und Ordnernamen: Das Diagnoselog nennt keine Namen (#647).
  Log(Format('Code-Vorlagen: %d eigene, %d fehlerhafte übersprungen; %d aus der IDE, %d übersprungen, ' +
    '%d Skripte entfallen; %d aus der Projektdatei, %d fehlerhafte übersprungen', [Integer(Length(mOwn)),
    Integer(Length(mErrors)), mStats.Templates, mStats.Skipped, mStats.Scripts, Integer(Length(mTeam)),
    Integer(Length(mTeamErrors))]));
  FSources.SetSnippetList(TAtlasSnippets.Merge(TAtlasSnippets.Merge(TAtlasSnippets.BuiltIn, mIde), mOwn));
end;

procedure TAtlasEditorCompletionSnippets.SendPostfixTemplates;
var
  mSession: TLspSession;
begin
  if not Assigned(FSession) then
  begin
    Exit;
  end;
  mSession := FSession();
  if (mSession = nil) or not mSession.Initialized then
  begin
    Exit;
  end;
  if (mSession = FSnippets.PostfixSession) and (TThread.GetTickCount64 - FSnippets.PostfixSent < cPostfixResendMs) then
  begin
    Exit;
  end;
  FSnippets.PostfixSession := mSession;
  FSnippets.PostfixSent := TThread.GetTickCount64;
  // Auch eine leere Liste: Gelöschte Vorlagen verschwinden beim Server.
  mSession.Notify('atlas/postfixTemplates', TAtlasSnippets.PostfixParams(FSnippets.Postfix));
end;

class function TAtlasEditorCompletionSnippets.IdeTemplateFolder: string;
var
  mServices: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Result := TAtlasLiveTemplates.Folder(TAtlasProjectContext.VersionOfRegistryKey(mServices.GetBaseRegistryKey));
  end;
end;

class function TAtlasEditorCompletionSnippets.SnippetFolder: string;
begin
  Result := GetEnvironmentVariable('APPDATA');
  if Result <> '' then
  begin
    Result := IncludeTrailingPathDelimiter(Result) + 'Atlas\Snippets';
  end;
end;

function TAtlasEditorCompletionSnippets.Snippets: TAtlasSnippetList;
begin
  Result := nil;
  if not TAtlasIdeSettings.Current.Snippets then
  begin
    Exit;
  end;
  RefreshSnippets;
  Result := FSources.SnippetList();
end;

function TAtlasEditorCompletionSnippets.FileSnippets: TAtlasSnippetList;
begin
  Result := nil;
  if not TAtlasIdeSettings.Current.Snippets then
  begin
    Exit;
  end;
  RefreshSnippets;
  Result := FSnippets.Files;
end;

end.
