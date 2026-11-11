unit Atlas.IDE.Editor.GhostSuggestions;

// Schattentext-Vorschläge nach Enter (#1890) im Editor: Anzeige, Tasten und
// Puffer für alle Anbieter aus Atlas.IDE.Contracts.GhostSuggestions (zuerst
// die gelernten Vorschläge, Atlas.IDE.Editor.LearnedSuggestions).
// - Auslöser ist Atlas.IDE.Editor.EnterWatch nach „Muster fortsetzen“ (#671):
//   Zeigt das Muster einen Vorschlag, fragt Atlas hier nicht. Der Handler
//   übernimmt die Zeile nie.
// - Nach der Tipp-Pause (suggestions.delayMs) fragt Atlas die Anbieter, wenn
//   die Schreibmarke noch am Ende der leeren Zeile steht und die Zeile darüber
//   unverändert ist; die Arbeit läuft im Hintergrund (TAtlasBackgroundRequest).
//   Hat sich bis zur Antwort etwas geändert, verfällt sie.
// - Anzeige wie beim Muster über TAtlasEditorPreview (Element PatternPreview):
//   eine Zeile, der Block in einer Zeile (TAtlasGhostText). Im Statusfeld
//   „gelernt aus N Stellen“ mit Belegen im Hinweis; ein Klick springt hin.
// - Tab schreibt den Rest als einen Rückgängig-Schritt, Strg+→ das nächste
//   Wort, Esc verwirft (der Anbieter zählt es). Ist alles geschrieben, steht
//   die Schreibmarke im Rumpf. Jede andere Änderung und jeder Wechsel der
//   Ansicht verwirft den Vorschlag.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.ExtCtrls,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Lsp.BackgroundRequest,
  Atlas.Core.Editor.LearnedSuggestions,
  Atlas.IDE.Contracts.GhostSuggestions,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Completion.Preview;

type
  /// <summary>Feld im Statusfeld setzen; leerer Text entfernt es.</summary>
  TAtlasGhostStatus = reference to procedure(const AText, AHint: string; const AOnClick: TProc<TPoint>);

  TAtlasIdeGhostSuggestions = class
  private const
    /// <summary>Wie beim Muster fortsetzen: nach der Vervollständigung, vor Parameterhilfe und Platzhaltern.
    /// </summary>
    cKeyPriority = 6;
  private type
    TKeys = class(TAtlasKeyClient)
    protected
      function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
      procedure HandleKey(AKey: Word; AShift: TShiftState); override;
    end;
    /// <summary>Ereignisse von Zeitgeber und Menü.</summary>
    TEvents = class
      procedure Tick(Sender: TObject);
      procedure LocationClick(Sender: TObject);
    end;
    /// <summary>Stand nach Enter bzw. beim Fragen.</summary>
    TAsked = record
      FileName: string;
      /// <summary>Leere Zeile, 0-basiert.</summary>
      Line: Integer;
      LineText: string;
      PreviousText: string;
    end;
  private class var
    FBusy: TFunc<Boolean>;
    FStatus: TAtlasGhostStatus;
    FPreview: TAtlasEditorPreview;
    FKeys: TKeys;
    FEvents: TEvents;
    FTimer: TTimer;
    FMenu: TPopupMenu;
    FRequest: TAtlasBackgroundRequest;
    FPending: TAsked;
    /// <summary>Sichtbarer Vorschlag: Datei, Schreibmarke (1-basiert), Anbieter, Vorschlag, Rest.</summary>
    FFileName: string;
    FLine: Integer;
    FColumn: Integer;
    FProvider: IAtlasGhostProvider;
    FProposal: TAtlasGhostProposal;
    FGhost: TAtlasGhostText;
    /// <summary>So viele Zeichen vor der Schreibmarke ersetzt das erste Schreiben (tiefer eingerückte Zeile).
    /// </summary>
    FReplace: Integer;
    /// <summary>Eigenes Schreiben: die folgende Änderung verwirft den Vorschlag nicht.</summary>
    FOwnWrite: Boolean;
    class function Run(const AView: IOTAEditView): Boolean; static;
    class function AskedOf(const AView: IOTAEditView; ALine: Integer): TAsked; static;
    /// <summary>Steht die Schreibmarke von AView noch am Ende der leeren Zeile aus AAsked, Zeile darüber gleich?
    /// </summary>
    class function StillAt(const AView: IOTAEditView; const AAsked: TAsked; ACompareLine: Boolean): Boolean;
      static;
    /// <summary>Darf in AView nach Enter gefragt werden (Quelltext, schreibbar, Atlas tippt nicht gerade)?
    /// </summary>
    class function CanAsk(const AView: IOTAEditView): Boolean; static;
    class function ContextOf(const AView: IOTAEditView; const AAsked: TAsked): TAtlasGhostContext; static;
    class procedure Ask; static;
    /// <summary>Fragt die Anbieter nacheinander im Hintergrund; der erste Vorschlag gewinnt.</summary>
    class procedure Start(const AAsked: TAsked; const AWorks: TArray<TAtlasGhostWork>;
      const AProviders: TArray<IAtlasGhostProvider>); static;
    class procedure Answered(const AAsked: TAsked; const AProvider: IAtlasGhostProvider;
      const AProposal: TAtlasGhostProposal); static;
    class procedure ShowGhost; static;
    class function AtSuggestion: Boolean; static;
    /// <summary>Schreibt AText an der Schreibmarke als einen Rückgängig-Schritt.</summary>
    class procedure WriteAtCursor(const AText: string); static;
    class procedure Finish; static;
    class procedure ClearStatus; static;
    class procedure StatusClick(APoint: TPoint); static;
  public
    /// <summary>Meldet den Handler nach Enter an. ABusy: Vervollständigung oder Platzhalter offen; AStatus: Feld im
    /// Statusfeld.</summary>
    class procedure Install(const ABusy: TFunc<Boolean>; const AStatus: TAtlasGhostStatus); static;
    class procedure Uninstall; static;
    class function Enabled: Boolean; static;
    class function Visible: Boolean; static;
    /// <summary>Vorschlag verwerfen, ohne den Anbieter zu benachrichtigen; die wartende Frage entfällt.</summary>
    class procedure Dismiss; static;
    /// <summary>Aus EditorViewModified: eine fremde Änderung verwirft einen sichtbaren Vorschlag.</summary>
    class procedure EditorModified; static;
    /// <summary>Tab: den ganzen Rest schreiben.</summary>
    class procedure AcceptAll; static;
    /// <summary>Strg+→: das nächste Wort schreiben.</summary>
    class procedure AcceptWord; static;
    /// <summary>Esc: verwerfen und dem Anbieter melden.</summary>
    class procedure Reject; static;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.SmartIndent,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Editor.EnterWatch;

const
  cHandlerName = 'GhostSuggestions';

{ TAtlasIdeGhostSuggestions.TKeys }

function TAtlasIdeGhostSuggestions.TKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := Visible and AtSuggestion and ((((AKey = VK_TAB) or (AKey = VK_ESCAPE)) and (AShift = [])) or
    ((AKey = VK_RIGHT) and (AShift = [ssCtrl])));
end;

procedure TAtlasIdeGhostSuggestions.TKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mKey: Word;
begin
  mKey := AKey;
  TAtlasGuard.Run(TAtlasFeature.LearnedSuggestions,
    procedure
    begin
      case mKey of
        VK_TAB:
          AcceptAll;
        VK_RIGHT:
          AcceptWord;
      else
        Reject;
      end;
    end);
end;

{ TAtlasIdeGhostSuggestions.TEvents }

procedure TAtlasIdeGhostSuggestions.TEvents.Tick(Sender: TObject);
begin
  FTimer.Enabled := False;
  TAtlasGuard.Run(TAtlasFeature.LearnedSuggestions, Ask);
end;

procedure TAtlasIdeGhostSuggestions.TEvents.LocationClick(Sender: TObject);
var
  mIndex: Integer;
  mLocations: TArray<TAtlasGhostLocation>;
begin
  mIndex := (Sender as TMenuItem).Tag;
  mLocations := FProposal.Locations;
  if (mIndex >= 0) and (mIndex <= High(mLocations)) then
  begin
    TAtlasGuard.Run(TAtlasFeature.LearnedSuggestions,
      procedure
      begin
        TAtlasIdeNavigation.GoToLocation(mLocations[mIndex].FileName, mLocations[mIndex].Line, 0);
      end);
  end;
end;

{ TAtlasIdeGhostSuggestions }

class procedure TAtlasIdeGhostSuggestions.Install(const ABusy: TFunc<Boolean>; const AStatus: TAtlasGhostStatus);
begin
  FBusy := ABusy;
  FStatus := AStatus;
  if FPreview = nil then
  begin
    FPreview := TAtlasEditorPreview.Create;
    FPreview.Element := TAtlasDrawnElement.PatternPreview;
    FPreview.FollowCursor := True;
  end;
  if FKeys = nil then
  begin
    FKeys := TKeys.Create(cKeyPriority);
  end;
  if FEvents = nil then
  begin
    FEvents := TEvents.Create;
  end;
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(nil);
    FTimer.Enabled := False;
    FTimer.OnTimer := FEvents.Tick;
  end;
  if FRequest = nil then
  begin
    FRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.LearnedSuggestions);
  end;
  TAtlasEnterWatch.Add(cHandlerName,
    function: Boolean
    begin
      Result := Enabled;
    end,
    function(const AView: IOTAEditView): Boolean
    begin
      Result := Run(AView);
    end);
end;

class procedure TAtlasIdeGhostSuggestions.Uninstall;
begin
  TAtlasEnterWatch.Remove(cHandlerName);
  Dismiss;
  if FKeys <> nil then
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
  // Wartet die laufende Anfrage ab und verwirft ihre Antwort.
  FreeAndNil(FRequest);
  FreeAndNil(FTimer);
  FreeAndNil(FMenu);
  FreeAndNil(FEvents);
  FreeAndNil(FKeys);
  FreeAndNil(FPreview);
  FBusy := nil;
  FStatus := nil;
end;

class function TAtlasIdeGhostSuggestions.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasGhostProviders.AnyEnabled;
end;

class function TAtlasIdeGhostSuggestions.Visible: Boolean;
begin
  Result := FFileName <> '';
end;

class procedure TAtlasIdeGhostSuggestions.ClearStatus;
begin
  if Assigned(FStatus) then
  begin
    FStatus('', '', nil);
  end;
end;

class procedure TAtlasIdeGhostSuggestions.Dismiss;
begin
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
  end;
  FPending := Default(TAsked);
  if FFileName = '' then
  begin
    Exit;
  end;
  FFileName := '';
  FProvider := nil;
  FProposal := Default(TAtlasGhostProposal);
  FGhost := Default(TAtlasGhostText);
  FOwnWrite := False;
  if FKeys <> nil then
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
  if FPreview <> nil then
  begin
    FPreview.Clear;
  end;
  ClearStatus;
end;

class procedure TAtlasIdeGhostSuggestions.EditorModified;
begin
  if Visible and FOwnWrite and AtSuggestion then
  begin
    Exit;
  end;
  // Die wartende Frage prüft beim Ablauf selbst, ob die Zeile noch leer ist (die Einrückung beim Tippen darf sie
  // noch ändern); nur ein sichtbarer Vorschlag verschwindet.
  if Visible then
  begin
    Dismiss;
  end;
end;

class function TAtlasIdeGhostSuggestions.AskedOf(const AView: IOTAEditView; ALine: Integer): TAsked;
begin
  Result.FileName := AView.Buffer.FileName;
  Result.Line := ALine;
  Result.LineText := TAtlasEditorBuffer.LineText(AView, ALine + 1);
  Result.PreviousText := TAtlasEditorBuffer.LineText(AView, ALine);
end;

class function TAtlasIdeGhostSuggestions.StillAt(const AView: IOTAEditView; const AAsked: TAsked;
  ACompareLine: Boolean): Boolean;
var
  mNow: TAsked;
  mCursor: TOTAEditPos;
begin
  Result := (AAsked.FileName <> '') and (AView <> nil) and (AView.Buffer <> nil) and
    (AView = TAtlasEditorBuffer.ActiveView) and SameText(AView.Buffer.FileName, AAsked.FileName) and
    not AView.Buffer.IsReadOnly;
  if not Result then
  begin
    Exit;
  end;
  mCursor := AView.CursorPos;
  mNow := AskedOf(AView, AAsked.Line);
  Result := (mCursor.Line - 1 = AAsked.Line) and (Trim(mNow.LineText) = '') and
    (mNow.PreviousText = AAsked.PreviousText) and
    (TLspSession.ColumnToIndex(mNow.LineText, mCursor.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer)) =
    Length(mNow.LineText));
  if Result and ACompareLine then
  begin
    Result := mNow.LineText = AAsked.LineText;
  end;
end;

class function TAtlasIdeGhostSuggestions.Run(const AView: IOTAEditView): Boolean;
begin
  Result := False;
  Dismiss;
  if (FTimer = nil) or not CanAsk(AView) then
  begin
    Exit;
  end;
  FPending := AskedOf(AView, AView.CursorPos.Line - 1);
  // Eine Zeile "/befehl" darüber gehört den Schnellbefehlen (#293).
  if not TAtlasSmartIndent.Applies(FPending.PreviousText) or (Trim(FPending.PreviousText) = '') then
  begin
    FPending := Default(TAsked);
    Exit;
  end;
  FTimer.Interval := TAtlasIdeSettings.Current.SuggestionsDelayMs;
  FTimer.Enabled := True;
end;

class function TAtlasIdeGhostSuggestions.CanAsk(const AView: IOTAEditView): Boolean;
begin
  Result := (AView <> nil) and (AView.Buffer <> nil) and not AView.Buffer.IsReadOnly and
    TAtlasSmartIndent.IsSource(AView.Buffer.FileName);
  if Result and Assigned(FBusy) then
  begin
    Result := not FBusy();
  end;
end;

class function TAtlasIdeGhostSuggestions.ContextOf(const AView: IOTAEditView; const AAsked: TAsked):
  TAtlasGhostContext;
begin
  Result.FileName := AAsked.FileName;
  Result.Line := AAsked.Line;
  Result.Text := TAtlasEditorBuffer.Text(AView.Buffer);
  Result.TabSize := TAtlasEditorBuffer.BlockIndent(AView.Buffer);
  Result.InsertSpaces := True;
end;

class procedure TAtlasIdeGhostSuggestions.Ask;
var
  mView: IOTAEditView;
  mAsked: TAsked;
  mContext: TAtlasGhostContext;
  mProvider: IAtlasGhostProvider;
  mWork: TAtlasGhostWork;
  mWorks: TArray<TAtlasGhostWork>;
  mProviders: TArray<IAtlasGhostProvider>;
begin
  mAsked := FPending;
  FPending := Default(TAsked);
  mView := TAtlasEditorBuffer.ActiveView;
  if (FRequest = nil) or FRequest.Busy or not CanAsk(mView) or not StillAt(mView, mAsked, False) then
  begin
    Exit;
  end;
  // Stand beim Fragen: Die Einrückung beim Tippen kann die Zeile nach Enter noch geändert haben.
  mAsked := AskedOf(mView, mAsked.Line);
  mContext := ContextOf(mView, mAsked);
  mWorks := nil;
  mProviders := nil;
  for mProvider in TAtlasGhostProviders.List do
  begin
    if not mProvider.Enabled then
    begin
      Continue;
    end;
    mWork := mProvider.Prepare(mContext);
    if Assigned(mWork) then
    begin
      mWorks := mWorks + [mWork];
      mProviders := mProviders + [mProvider];
    end;
  end;
  if mWorks <> nil then
  begin
    Start(mAsked, mWorks, mProviders);
  end;
end;

class procedure TAtlasIdeGhostSuggestions.Start(const AAsked: TAsked; const AWorks: TArray<TAtlasGhostWork>;
  const AProviders: TArray<IAtlasGhostProvider>);
var
  mAsked: TAsked;
  mWorks: TArray<TAtlasGhostWork>;
  mProviders: TArray<IAtlasGhostProvider>;
  mFound: IAtlasGhostProvider;
  mProposal: TAtlasGhostProposal;
begin
  // Kopien: Anonyme Methoden fangen keine const-Parameter ein.
  mAsked := AAsked;
  mWorks := AWorks;
  mProviders := AProviders;
  mFound := nil;
  mProposal := Default(TAtlasGhostProposal);
  FRequest.Start(
    procedure
    var
      mIndex: Integer;
    begin
      for mIndex := 0 to High(mWorks) do
      begin
        if mWorks[mIndex](mProposal) then
        begin
          mFound := mProviders[mIndex];
          Exit;
        end;
      end;
    end,
    procedure(AOk: Boolean; const AError: string)
    begin
      if AOk and (mFound <> nil) then
      begin
        Answered(mAsked, mFound, mProposal);
      end;
    end);
end;

class procedure TAtlasIdeGhostSuggestions.Answered(const AAsked: TAsked; const AProvider: IAtlasGhostProvider;
  const AProposal: TAtlasGhostProposal);
var
  mView: IOTAEditView;
  mBlock, mLineBreak, mText: string;
  mWritten: Integer;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  if Visible or (Length(AProposal.Lines) = 0) or not StillAt(mView, AAsked, True) or
    (Assigned(FBusy) and FBusy()) then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  mLineBreak := #10;
  if Pos(#13#10, mText) > 0 then
  begin
    mLineBreak := #13#10;
  end;
  mBlock := string.Join(mLineBreak, AProposal.Lines);
  mWritten := TAtlasLearnedSuggestions.Written(mBlock, AAsked.LineText);
  FReplace := 0;
  if mWritten = 0 then
  begin
    FReplace := Length(AAsked.LineText);
  end;
  FGhost := TAtlasGhostText.Create(mBlock, mWritten);
  if FGhost.Finished then
  begin
    Exit;
  end;
  FFileName := AAsked.FileName;
  FLine := mView.CursorPos.Line;
  FColumn := mView.CursorPos.Col;
  FProvider := AProvider;
  FProposal := AProposal;
  TAtlasKeyHook.Add(FKeys);
  ShowGhost;
  if Assigned(FStatus) then
  begin
    FStatus(AProposal.StatusText, AProposal.Hint,
      procedure(APoint: TPoint)
      begin
        StatusClick(APoint);
      end);
  end;
end;

class procedure TAtlasIdeGhostSuggestions.ShowGhost;
begin
  FPreview.Show(FFileName, FLine, FColumn, FGhost.Display);
end;

class function TAtlasIdeGhostSuggestions.AtSuggestion: Boolean;
var
  mView: IOTAEditView;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  Result := (mView <> nil) and (mView.Buffer <> nil) and SameText(mView.Buffer.FileName, FFileName) and
    (mView.CursorPos.Line = FLine) and (mView.CursorPos.Col = FColumn);
end;

class procedure TAtlasIdeGhostSuggestions.WriteAtCursor(const AText: string);
var
  mView: IOTAEditView;
  mBuffer: IOTAEditBuffer;
  mWriter: IOTAEditWriter;
  mText, mLineText: string;
  mLine, mCharacter, mTabWidth: Integer;
  mLines: TArray<string>;
  mTarget: TOTAEditPos;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  mBuffer := mView.Buffer;
  mText := TAtlasEditorBuffer.Text(mBuffer);
  mTabWidth := TAtlasEditorBuffer.TabWidth(mBuffer);
  mLine := FLine - 1;
  mLineText := TAtlasEditorBuffer.LineText(mView, FLine);
  mCharacter := TLspSession.ColumnToIndex(mLineText, FColumn, mTabWidth);
  FOwnWrite := True;
  mWriter := mBuffer.CreateUndoableWriter;
  mWriter.CopyTo(TAtlasEditorBuffer.ByteOffset(mText, mLine, mCharacter - FReplace));
  mWriter.DeleteTo(TAtlasEditorBuffer.ByteOffset(mText, mLine, mCharacter));
  mWriter.Insert(PAnsiChar(UTF8Encode(AText)));
  mWriter := nil;
  TAtlasEditorSnapshots.Invalidate(mBuffer.FileName);
  // Schreibmarke ans Ende des Geschriebenen.
  mLines := AText.Split([#13#10, #10]);
  mCharacter := mCharacter - FReplace;
  FReplace := 0;
  if Length(mLines) > 1 then
  begin
    Inc(mLine, High(mLines));
    mCharacter := Length(mLines[High(mLines)]);
  end
  else
  begin
    Inc(mCharacter, Length(AText));
  end;
  mTarget.Line := mLine + 1;
  mTarget.Col := TLspSession.IndexToColumn(TAtlasEditorBuffer.LineText(mView, mTarget.Line), mCharacter, mTabWidth);
  mView.CursorPos := mTarget;
  mView.MoveViewToCursor;
  FLine := mTarget.Line;
  FColumn := mTarget.Col;
  // Die Änderung kommt über EditorViewModified, danach gilt jede Änderung wieder als fremd.
  TAtlasMainThread.ForceQueue(TAtlasFeature.LearnedSuggestions,
    procedure
    begin
      FOwnWrite := False;
    end);
end;

class procedure TAtlasIdeGhostSuggestions.Finish;
var
  mView: IOTAEditView;
  mTarget: TOTAEditPos;
  mProvider: IAtlasGhostProvider;
  mProposal: TAtlasGhostProposal;
begin
  mProvider := FProvider;
  mProposal := FProposal;
  Dismiss;
  mView := TAtlasEditorBuffer.ActiveView;
  if mView <> nil then
  begin
    mTarget.Line := mProposal.CursorLine + 1;
    mTarget.Col := TLspSession.IndexToColumn(TAtlasEditorBuffer.LineText(mView, mTarget.Line),
      mProposal.CursorCharacter, TAtlasEditorBuffer.TabWidth(mView.Buffer));
    mView.CursorPos := mTarget;
    mView.MoveViewToCursor;
    mView.Paint;
  end;
  if mProvider <> nil then
  begin
    mProvider.Accepted(mProposal);
  end;
end;

class procedure TAtlasIdeGhostSuggestions.AcceptAll;
begin
  if not Visible or not AtSuggestion then
  begin
    Dismiss;
    Exit;
  end;
  WriteAtCursor(FGhost.Rest);
  Finish;
end;

class procedure TAtlasIdeGhostSuggestions.AcceptWord;
var
  mWord: string;
begin
  if not Visible or not AtSuggestion then
  begin
    Dismiss;
    Exit;
  end;
  mWord := FGhost.NextWord;
  WriteAtCursor(mWord);
  FGhost.Advance(mWord);
  if FGhost.Finished then
  begin
    Finish;
    Exit;
  end;
  ShowGhost;
  TAtlasEditorBuffer.ActiveView.Paint;
end;

class procedure TAtlasIdeGhostSuggestions.Reject;
var
  mProvider: IAtlasGhostProvider;
  mProposal: TAtlasGhostProposal;
begin
  mProvider := FProvider;
  mProposal := FProposal;
  Dismiss;
  if mProvider <> nil then
  begin
    mProvider.Rejected(mProposal);
  end;
end;

class procedure TAtlasIdeGhostSuggestions.StatusClick(APoint: TPoint);
var
  mIndex: Integer;
  mItem: TMenuItem;
  mEvidence: TAtlasLearnedEvidence;
begin
  if not Visible or (Length(FProposal.Locations) = 0) then
  begin
    Exit;
  end;
  FreeAndNil(FMenu);
  FMenu := TPopupMenu.Create(nil);
  for mIndex := 0 to High(FProposal.Locations) do
  begin
    mEvidence.FileName := FProposal.Locations[mIndex].FileName;
    mEvidence.Line := FProposal.Locations[mIndex].Line;
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := TAtlasLearnedSuggestions.EvidenceText(mEvidence);
    mItem.Tag := mIndex;
    mItem.OnClick := FEvents.LocationClick;
    FMenu.Items.Add(mItem);
  end;
  FMenu.Popup(APoint.X, APoint.Y);
end;

end.
