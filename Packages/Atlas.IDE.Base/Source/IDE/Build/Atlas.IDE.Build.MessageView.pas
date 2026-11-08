unit Atlas.IDE.Build.MessageView;

// Compilermeldungen aus dem Meldungsfenster der IDE lesen (#528). Die Open
// Tools API kann Meldungen nur hinzufügen, nicht lesen.
//
// Gewählter Weg (Spike in RAD Studio 13, 10.10.2026): Der Reiter „Build“ ist
// ein selbst gezeichneter Virtual Tree (TMessageViewForm › MessageTreeView0,
// Klasse TBetterHintWindowVirtualDrawTree) ohne Text-Eigenschaft. Über RTTI
// sind GetFirst/GetNext/GetNodeData erreichbar; hinter den Knotendaten liegen
// Objekte der IDE. Meldungen des Compilers sind TCompilerMsgLine-Nachfahren
// (TToolCompilerMessageLine) mit den Eigenschaften Kind (msgError, msgWarning,
// msgHint, msgInfo …), Message ("E2003 …"), FileName, Line und Column.
// Ohne Zwischenablage, ohne Fenster nach vorn zu holen, im Hauptthread.
// Ausweichwege, falls eine IDE-Version das ändert: „Alles auswählen“ +
// „Kopieren“ über die Zwischenablage oder der Reiter
// „Ausgabe“ bei ausführlicher Compilerausgabe. Ist der Baum nicht lesbar,
// meldet Read das mit Grund; Atlas arbeitet dann ohne Compilermeldungen.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages;

type
  TAtlasMessageView = class
  public
    /// <summary>Compilermeldungen des Reiters „Build“; False mit Grund in AInfo, wenn er nicht lesbar ist.</summary>
    class function Read(out AMessages: TArray<TAtlasCompilerMessage>; out AInfo: string): Boolean; static;
  end;

  /// <summary>AReadable: Der Reiter war lesbar (sonst sind AMessages leer und sagen nichts über den Lauf).</summary>
  TAtlasMessagesProc = reference to procedure(const AMessages: TArray<TAtlasCompilerMessage>;
    const AProject: TAtlasCompileProject; ASucceeded: Boolean; const AInfo: string; AReadable: Boolean);

  /// <summary>Liest nach jedem Compile den Reiter „Build“ und gibt die Meldungen weiter (#528).</summary>
  TAtlasMessageViewReader = class(TAtlasCompileParticipant)
  private
    FOnMessages: TAtlasMessagesProc;
    FPending: Boolean;
    FProject: TAtlasCompileProject;
    FSucceeded: Boolean;
    procedure ReadSoon(ASucceeded: Boolean);
  public
    /// <summary>AOnMessages im Hauptthread, nachdem die IDE die Meldungen eingetragen hat.</summary>
    constructor Create(const AOnMessages: TAtlasMessagesProc);
    procedure ProjectStarted(const AProject: TAtlasCompileProject); override;
    procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); override;
    procedure ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean; ADurationMs: Int64); override;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Winapi.Windows,
  System.Rtti,
  System.TypInfo,
  Vcl.Forms;

const
  cFormClass = 'TMessageViewForm';
  cTreeNamePart = 'MESSAGETREEVIEW';
  cMessageLineClass = 'TCompilerMsgLine';
  cMaxNodes = 20000;

function FindTree(AOwner: TComponent): TComponent;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AOwner.ComponentCount - 1 do
  begin
    if Pos(cTreeNamePart, UpperCase(AOwner.Components[mIndex].Name)) > 0 then
    begin
      Exit(AOwner.Components[mIndex]);
    end;
    Result := FindTree(AOwner.Components[mIndex]);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
end;

function MethodWith(AType: TRttiType; const AName: string; AParamCount: Integer): TRttiMethod;
var
  mMethod: TRttiMethod;
begin
  for mMethod in AType.GetMethods(AName) do
  begin
    if Length(mMethod.GetParameters) = AParamCount then
    begin
      Exit(mMethod);
    end;
  end;
  Result := nil;
end;

/// <summary>Argument für einen Parameter vom Typ PVirtualNode (Zeiger).</summary>
function PointerArg(AParameter: TRttiParameter; APointer: Pointer): TValue;
begin
  TValue.Make(@APointer, AParameter.ParamType.Handle, Result);
end;

/// <summary>APointer zeigt auf ein Delphi-Objekt (Klassenzeiger zeigt auf sich selbst), ohne Zugriffsfehler.</summary>
function LooksLikeObject(APointer: Pointer): Boolean;
var
  mInfo: TMemoryBasicInformation;
  mClassPtr: Pointer;
begin
  Result := False;
  if (APointer = nil) or (VirtualQuery(APointer, mInfo, SizeOf(mInfo)) = 0) or (mInfo.State <> MEM_COMMIT) then
  begin
    Exit;
  end;
  mClassPtr := PPointer(APointer)^;
  if (mClassPtr = nil) or (VirtualQuery(PByte(mClassPtr) + vmtSelfPtr, mInfo, SizeOf(mInfo)) = 0) or
    (mInfo.State <> MEM_COMMIT) then
  begin
    Exit;
  end;
  Result := PPointer(PByte(mClassPtr) + vmtSelfPtr)^ = mClassPtr;
end;

function InheritsFromName(AObject: TObject; const AClassName: string): Boolean;
var
  mClassType: TClass;
begin
  mClassType := AObject.ClassType;
  while mClassType <> nil do
  begin
    if SameText(mClassType.ClassName, AClassName) then
    begin
      Exit(True);
    end;
    mClassType := mClassType.ClassParent;
  end;
  Result := False;
end;

function PropValue(AContext: TRttiContext; AObject: TObject; const AName: string): TValue;
var
  mProp: TRttiProperty;
begin
  mProp := AContext.GetType(AObject.ClassType).GetProperty(AName);
  if (mProp = nil) or not mProp.IsReadable then
  begin
    Exit(TValue.Empty);
  end;
  Result := mProp.GetValue(AObject);
end;

function AsInt(const AValue: TValue): Integer;
begin
  if AValue.IsOrdinal then
  begin
    Result := AValue.AsOrdinal;
  end
  else
  begin
    Result := 0;
  end;
end;

{ TAtlasMessageViewReader }

constructor TAtlasMessageViewReader.Create(const AOnMessages: TAtlasMessagesProc);
begin
  inherited Create;
  FOnMessages := AOnMessages;
end;

procedure TAtlasMessageViewReader.ProjectStarted(const AProject: TAtlasCompileProject);
begin
  FProject := AProject;
end;

procedure TAtlasMessageViewReader.ReadSoon(ASucceeded: Boolean);
begin
  FSucceeded := ASucceeded;
  // Ein Lesen je Lauf: Gruppe und Projekte melden das Ende kurz nacheinander.
  if FPending then
  begin
    Exit;
  end;
  FPending := True;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Build,
    procedure
    var
      Messages: TArray<TAtlasCompilerMessage>;
      Info: string;
      Readable: Boolean;
    begin
      FPending := False;
      Messages := nil;
      Readable := False;
      try
        Readable := TAtlasMessageView.Read(Messages, Info);
      except
        on E: Exception do
          Info := Info + '; ' + E.ClassName + ': ' + E.Message;
      end;
      if Assigned(FOnMessages) then
      begin
        FOnMessages(Messages, FProject, FSucceeded, Info, Readable);
      end;
    end);
end;

procedure TAtlasMessageViewReader.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
  // Dauer des ganzen Laufs für die Zusammenfassung der Projektgruppe (#758); das Lesen wartet ohnehin auf die
  // Nachrichtenschleife.
  FProject.GroupDurationMs := ADurationMs;
  ReadSoon(ASucceeded);
end;

procedure TAtlasMessageViewReader.ProjectFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
begin
  FProject := AProject;
  // Build-Dauer für den Projektverlauf (#758).
  FProject.DurationMs := ADurationMs;
  ReadSoon(ASucceeded);
end;

{ TAtlasMessageView }

/// <summary>Meldungsbaum des Meldungsfensters; nil mit Grund in AInfo.</summary>
function MessageTree(out AInfo: string): TComponent;
var
  mIndex: Integer;
  mForm: TForm;
begin
  Result := nil;
  mForm := nil;
  for mIndex := 0 to Screen.FormCount - 1 do
  begin
    if SameText(Screen.Forms[mIndex].ClassName, cFormClass) then
    begin
      mForm := Screen.Forms[mIndex];
    end;
  end;
  if mForm = nil then
  begin
    AInfo := cFormClass + ' nicht gefunden';
  end
  else
  begin
    Result := FindTree(mForm);
    if Result = nil then
    begin
      AInfo := 'Meldungsbaum nicht gefunden';
    end;
  end;
end;

/// <summary>Meldung aus den Daten eines Knotens; False, wenn es keine Compilermeldung ist.</summary>
function MessageOf(const AContext: TRttiContext; AData: Pointer; out AMessage: TAtlasCompilerMessage): Boolean;
var
  mLine: TObject;
begin
  Result := (AData <> nil) and LooksLikeObject(PPointer(AData)^);
  if not Result then
  begin
    Exit;
  end;
  mLine := TObject(PPointer(AData)^);
  Result := InheritsFromName(mLine, cMessageLineClass);
  if Result then
  begin
    AMessage := TAtlasCompilerMessages.FromIde(PropValue(AContext, mLine, 'Kind').ToString,
      PropValue(AContext, mLine, 'Message').ToString, PropValue(AContext, mLine, 'FileName').ToString,
      AsInt(PropValue(AContext, mLine, 'Line')), AsInt(PropValue(AContext, mLine, 'Column')));
  end;
end;

type
  /// <summary>Durchlauf durch den Baum über RTTI; je nach Version mit oder ohne ConsiderChildrenAbove.</summary>
  TTreeWalk = record
    Tree: TComponent;
    GetFirst: TRttiMethod;
    GetNext: TRttiMethod;
    GetNodeData: TRttiMethod;
    /// <summary>Methoden suchen; False mit Grund in AInfo, wenn eine fehlt.</summary>
    function Resolve(const AContext: TRttiContext; out AInfo: string): Boolean;
    function First: Pointer;
    function Next(ANode: Pointer): Pointer;
    function DataOf(ANode: Pointer): Pointer;
  end;

function TTreeWalk.Resolve(const AContext: TRttiContext; out AInfo: string): Boolean;
var
  mType: TRttiType;
begin
  mType := AContext.GetType(Tree.ClassType);
  GetFirst := MethodWith(mType, 'GetFirst', 1);
  if GetFirst = nil then
  begin
    GetFirst := MethodWith(mType, 'GetFirst', 0);
  end;
  GetNext := MethodWith(mType, 'GetNext', 2);
  if GetNext = nil then
  begin
    GetNext := MethodWith(mType, 'GetNext', 1);
  end;
  GetNodeData := MethodWith(mType, 'GetNodeData', 1);
  Result := (GetFirst <> nil) and (GetNext <> nil) and (GetNodeData <> nil);
  if not Result then
  begin
    AInfo := Format('%s: über RTTI nicht erreichbar (GetFirst %s, GetNext %s, GetNodeData %s)', [Tree.ClassName,
      BoolToStr(GetFirst <> nil, True), BoolToStr(GetNext <> nil, True), BoolToStr(GetNodeData <> nil, True)]);
  end;
end;

function TTreeWalk.First: Pointer;
begin
  if Length(GetFirst.GetParameters) = 1 then
  begin
    Result := GetFirst.Invoke(Tree, [False]).AsType<Pointer>;
  end
  else
  begin
    Result := GetFirst.Invoke(Tree, []).AsType<Pointer>;
  end;
end;

function TTreeWalk.Next(ANode: Pointer): Pointer;
begin
  if Length(GetNext.GetParameters) = 2 then
  begin
    Result := GetNext.Invoke(Tree, [PointerArg(GetNext.GetParameters[0], ANode), False]).AsType<Pointer>;
  end
  else
  begin
    Result := GetNext.Invoke(Tree, [PointerArg(GetNext.GetParameters[0], ANode)]).AsType<Pointer>;
  end;
end;

function TTreeWalk.DataOf(ANode: Pointer): Pointer;
begin
  Result := GetNodeData.Invoke(Tree, [PointerArg(GetNodeData.GetParameters[0], ANode)]).AsType<Pointer>;
end;

class function TAtlasMessageView.Read(out AMessages: TArray<TAtlasCompilerMessage>; out AInfo: string): Boolean;
var
  mCount: Integer;
  mContext: TRttiContext;
  mWalk: TTreeWalk;
  mNode: Pointer;
  mMessage: TAtlasCompilerMessage;
begin
  Result := False;
  AMessages := nil;
  mWalk := Default(TTreeWalk);
  mWalk.Tree := MessageTree(AInfo);
  if mWalk.Tree = nil then
  begin
    Exit;
  end;
  mContext := TRttiContext.Create;
  try
    if not mWalk.Resolve(mContext, AInfo) then
    begin
      Exit;
    end;
    mNode := mWalk.First;
    mCount := 0;
    while (mNode <> nil) and (mCount < cMaxNodes) do
    begin
      if MessageOf(mContext, mWalk.DataOf(mNode), mMessage) and
        (mMessage.Severity <> TAtlasCompilerSeverity.Info) then
      begin
        AMessages := AMessages + [mMessage];
      end;
      mNode := mWalk.Next(mNode);
      Inc(mCount);
    end;
    AInfo := Format('%d Knoten, %d Meldungen', [mCount, Length(AMessages)]);
    Result := True;
  finally
    mContext.Free;
  end;
end;

end.