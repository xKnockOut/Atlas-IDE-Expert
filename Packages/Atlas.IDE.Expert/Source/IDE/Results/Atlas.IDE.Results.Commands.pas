unit Atlas.IDE.Results.Commands;

// Befehle des Ergebnisfensters (#400) im Menü Atlas und in der
// Befehlspalette: Referenzen (samt Fundstellen in .dfm) und
// Implementierungen des Symbols am Cursor, Aufrufer und Aufrufe, Vorfahren und
// Nachfahren als Baum, dessen Ebenen beim Aufklappen nachgeladen werden, und
// die projektweite Symbolsuche in einem Fenster wie die Befehlspalette.
// Vor jeder Anfrage bekommt der Server den aktuellen Text der offenen Dateien.
// Meldungen nur als Zeile in der Meldungsansicht, nie als Dialog.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Results.Model;

type
  TAtlasIdeResults = class
  private
    class var FSessionOf: TFunc<TLspSession>;
    class var FMessage: TProc<string>;
    class procedure Say(const AText: string); static;
    /// <summary>Symbol am Cursor: Datei, Position und Name; False (mit Meldung) ohne Server oder Editor.</summary>
    class function AtCursor(out AFileName: string; out ALine, ACharacter: Integer; out AName: string): Boolean; static;
    class function Entries(const ALocations: TArray<TLspLocation>): TArray<TAtlasResultEntry>; static;
  public
    /// <summary>ASessionOf: laufende Sitzung oder nil; AMessage: Zeile für die Meldungsansicht.</summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>Laufende Sitzung oder nil; startet keinen Server (auch für das Suchfeld der Willkommensseite, #760).</summary>
    class function Session: TLspSession; static;
    class procedure FindReferences; static;
    class procedure FindImplementations; static;
    class procedure ShowHierarchy(ADirection: TAtlasHierarchyDirection); static;
    class procedure SearchSymbol; static;
    /// <summary>Referenzen auf ein Symbol an einem Fundort (z. B. aus dem Tooltip); Anzahl der Fundstellen.</summary>
    class function ShowReferences(const AFileName: string; ALine, ACharacter: Integer; const AName: string): Integer; static;
    /// <summary>Ergebnisfenster zeigen.</summary>
    class procedure ShowWindow; static;
    class procedure Open(const AFileName: string; ALine, ACharacter: Integer); static;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Diagnostics.Guard,
  Vcl.Controls,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Completion.Word,
  Atlas.Core.Commands.Palette,
  Atlas.UI.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Results.Window,
  Atlas.IDE.Foundation.Navigation;

const
  // Projektweit über viele Units; deutlich länger als ein Hover.
  SearchTimeoutMs = 30000;
  // Beim Tippen: lieber leer als die IDE aufhalten.
  SymbolTimeoutMs = 1500;

function ReadText(const AFileName: string): string;
begin
  Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
end;

{ TAtlasIdeResults }

class procedure TAtlasIdeResults.Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>);
begin
  FSessionOf := ASessionOf;
  FMessage := AMessage;
  TAtlasIdeResultsWindow.OnOpen :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.Results,
        procedure
        begin
          Open(AFileName, ALine, ACharacter);
        end);
    end;
  TAtlasIdeResultsWindow.OnExpand :=
    function(ADirection: TAtlasHierarchyDirection; const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>
    var
      Children: TArray<TAtlasHierarchyItem>;
    begin
      Children := nil;
      TAtlasGuard.Run(TAtlasFeature.Results,
        procedure
        var
          Current: TLspSession;
        begin
          Current := Session;
          if Current = nil then
            Exit;
          try
            Children := Current.HierarchyChildren(ADirection, AItem);
          except
            on E: ELspClientError do
              Say(TAtlasStrings.Fmt(TAtlasTextId.ResultsFailed, [E.Message]));
          end;
        end);
      Result := Children;
    end;
end;

class procedure TAtlasIdeResults.Uninstall;
begin
  FSessionOf := nil;
  FMessage := nil;
  TAtlasIdeResultsWindow.Release;
end;

class function TAtlasIdeResults.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
    Result := FSessionOf();
end;

class procedure TAtlasIdeResults.Say(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

class procedure TAtlasIdeResults.Open(const AFileName: string; ALine, ACharacter: Integer);
begin
  TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
end;

class function TAtlasIdeResults.AtCursor(out AFileName: string; out ALine, ACharacter: Integer;
  out AName: string): Boolean;
var
  Current: TLspSession;
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
  Cursor: TOTAEditPos;
  First, Last: Integer;
begin
  Result := False;
  AFileName := '';
  ALine := 0;
  ACharacter := 0;
  AName := '';
  Current := Session;
  if Current = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  View := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    View := Editors.TopView;
  if (View = nil) or (View.Buffer = nil) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  AFileName := View.Buffer.FileName;
  // Projektweite Anfragen: Der Server soll den Stand aller offenen Puffer kennen.
  TAtlasIdeRename.SyncOpenBuffers(Current);
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Current.Sync(AFileName, Text);
  Lines := Text.Split([#13#10, #10]);
  Cursor := View.CursorPos;
  if (Cursor.Line < 1) or (Cursor.Line > Length(Lines)) then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  ALine := Cursor.Line - 1;
  ACharacter := TLspSession.ColumnToIndex(Lines[ALine], Cursor.Col, TAtlasEditorBuffer.TabWidth(View.Buffer));
  First := TAtlasWord.StartBefore(Lines[ALine], ACharacter);
  Last := TAtlasWord.EndAfter(Lines[ALine], ACharacter);
  AName := Copy(Lines[ALine], First + 1, Last - First);
  Result := True;
end;

class function TAtlasIdeResults.Entries(const ALocations: TArray<TLspLocation>): TArray<TAtlasResultEntry>;
var
  Location: TLspLocation;
begin
  Result := nil;
  for Location in ALocations do
    Result := Result + [TAtlasResultEntry.Create(Location.FileName, Location.Line, Location.Character)];
  TAtlasResults.FillText(Result,
    function(const AFileName: string): string
    begin
      Result := ReadText(AFileName);
    end);
end;

class function TAtlasIdeResults.ShowReferences(const AFileName: string; ALine, ACharacter: Integer;
  const AName: string): Integer;
var
  Current: TLspSession;
  Found: TArray<TAtlasResultEntry>;
begin
  Result := 0;
  Current := Session;
  if Current = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  Screen.Cursor := crHourGlass;
  try
    try
      Found := Entries(Current.References(AFileName, ALine, ACharacter));
    except
      on E: ELspClientError do
      begin
        Say(TAtlasStrings.Fmt(TAtlasTextId.ResultsFailed, [E.Message]));
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  Result := Length(Found);
  TAtlasIdeResultsWindow.ShowEntries(TAtlasStrings.Fmt(TAtlasTextId.ResultsReferences,
    [AName, Length(Found), Length(TAtlasResults.Group(Found))]), Found);
end;

class procedure TAtlasIdeResults.FindReferences;
var
  FileName, Name: string;
  Line, Character: Integer;
begin
  if AtCursor(FileName, Line, Character, Name) then
    ShowReferences(FileName, Line, Character, Name);
end;

class procedure TAtlasIdeResults.FindImplementations;
var
  FileName, Name: string;
  Line, Character: Integer;
  Found: TArray<TAtlasResultEntry>;
begin
  if not AtCursor(FileName, Line, Character, Name) then
    Exit;
  Screen.Cursor := crHourGlass;
  try
    try
      Found := Entries(Session.Implementations(FileName, Line, Character));
    except
      on E: ELspClientError do
      begin
        Say(TAtlasStrings.Fmt(TAtlasTextId.ResultsFailed, [E.Message]));
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  // Genau eine Implementierung: gleich hinspringen wie „Gehe zu“.
  if Length(Found) = 1 then
  begin
    Open(Found[0].FileName, Found[0].Line, Found[0].Character);
    Exit;
  end;
  if Length(Found) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  TAtlasIdeResultsWindow.ShowEntries(TAtlasStrings.Fmt(TAtlasTextId.ResultsImplementations,
    [Name, Length(Found), Length(TAtlasResults.Group(Found))]), Found);
end;

class procedure TAtlasIdeResults.ShowHierarchy(ADirection: TAtlasHierarchyDirection);
const
  Titles: array[TAtlasHierarchyDirection] of TAtlasTextId = (TAtlasTextId.ResultsIncoming,
    TAtlasTextId.ResultsOutgoing, TAtlasTextId.ResultsSupertypes, TAtlasTextId.ResultsSubtypes);
var
  FileName, Name: string;
  Line, Character: Integer;
  Roots: TArray<TAtlasHierarchyItem>;
begin
  if not AtCursor(FileName, Line, Character, Name) then
    Exit;
  Screen.Cursor := crHourGlass;
  try
    try
      Roots := Session.PrepareHierarchy(ADirection, FileName, Line, Character);
    except
      on E: ELspClientError do
      begin
        Say(TAtlasStrings.Fmt(TAtlasTextId.ResultsFailed, [E.Message]));
        Exit;
      end;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  if Length(Roots) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  TAtlasIdeResultsWindow.ShowHierarchy(TAtlasStrings.Fmt(Titles[ADirection], [Roots[0].Name]), ADirection, Roots);
end;

class procedure TAtlasIdeResults.SearchSymbol;
var
  Window: TAtlasPaletteWindow;
  Symbols: TArray<TAtlasSymbol>;
  Area: TRect;
begin
  if Session = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  Symbols := nil;
  Window := TAtlasPaletteWindow.CreatePalette(Application, nil, nil, TAtlasIdeStyle.Colors);
  Window.Prompt := '#';
  Window.OnQuery :=
    function(APattern: string): TArray<TAtlasCommand>
    var
      Current: TLspSession;
      Index: Integer;
      Command: TAtlasCommand;
    begin
      Result := nil;
      Symbols := nil;
      Current := Session;
      if (Current = nil) or (Trim(APattern) = '') then
        Exit;
      try
        Symbols := Current.WorkspaceSymbols(Trim(APattern), SymbolTimeoutMs);
      except
        on ELspClientError do
          Symbols := nil;
      end;
      for Index := 0 to High(Symbols) do
      begin
        Command := Default(TAtlasCommand);
        Command.Id := IntToStr(Index);
        Command.Caption := Symbols[Index].Name;
        Command.Path := ExtractFileName(Symbols[Index].FileName);
        if Symbols[Index].Container <> '' then
          Command.Path := Symbols[Index].Container + ' · ' + Command.Path;
        Command.ShortCut := TAtlasResults.SymbolBadge(Symbols[Index].Kind);
        Result := Result + [Command];
      end;
    end;
  Window.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    var
      Index: Integer;
    begin
      Index := StrToIntDef(ACommand.Id, -1);
      if (Index >= 0) and (Index <= High(Symbols)) then
        Open(Symbols[Index].FileName, Symbols[Index].Line, Symbols[Index].Character);
    end;
  if Screen.ActiveForm <> nil then
    Area := Screen.ActiveForm.BoundsRect
  else if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  Window.ShowOver(Area);
end;

class procedure TAtlasIdeResults.ShowWindow;
begin
  TAtlasIdeResultsWindow.Frame;
end;

end.
