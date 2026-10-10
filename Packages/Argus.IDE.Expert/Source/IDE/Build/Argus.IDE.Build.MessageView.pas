unit Argus.IDE.Build.MessageView;

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
// „Kopieren“ über die Zwischenablage (so Claude-Compile) oder der Reiter
// „Ausgabe“ bei ausführlicher Compilerausgabe. Ist der Baum nicht lesbar,
// meldet Read das mit Grund; Argus arbeitet dann ohne Compilermeldungen.

interface

uses
  System.SysUtils,
  System.Classes,
  Argus.Core.Build.Events,
  Argus.Core.Build.Messages;

type
  TArgusMessageView = class
  public
    /// <summary>Compilermeldungen des Reiters „Build“; False mit Grund in AInfo, wenn er nicht lesbar ist.</summary>
    class function Read(out AMessages: TArray<TArgusCompilerMessage>; out AInfo: string): Boolean; static;
  end;

  TArgusMessagesProc = reference to procedure(const AMessages: TArray<TArgusCompilerMessage>;
    const AProject: TArgusCompileProject; ASucceeded: Boolean; const AInfo: string);

  /// <summary>Liest nach jedem Compile den Reiter „Build“ und gibt die Meldungen weiter (#528).</summary>
  TArgusMessageViewReader = class(TArgusCompileParticipant)
  private
    FOnMessages: TArgusMessagesProc;
    FPending: Boolean;
    FProject: TArgusCompileProject;
    FSucceeded: Boolean;
    procedure ReadSoon(ASucceeded: Boolean);
  public
    /// <summary>AOnMessages im Hauptthread, nachdem die IDE die Meldungen eingetragen hat.</summary>
    constructor Create(const AOnMessages: TArgusMessagesProc);
    procedure ProjectStarted(const AProject: TArgusCompileProject); override;
    procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); override;
    procedure ProjectFinished(const AProject: TArgusCompileProject; ASucceeded: Boolean; ADurationMs: Int64); override;
  end;

implementation

uses
  Winapi.Windows,
  System.Rtti,
  System.TypInfo,
  Vcl.Forms;

const
  FormClass = 'TMessageViewForm';
  TreeNamePart = 'MESSAGETREEVIEW';
  MessageLineClass = 'TCompilerMsgLine';
  MaxNodes = 20000;

function FindTree(AOwner: TComponent): TComponent;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to AOwner.ComponentCount - 1 do
  begin
    if Pos(TreeNamePart, UpperCase(AOwner.Components[Index].Name)) > 0 then
      Exit(AOwner.Components[Index]);
    Result := FindTree(AOwner.Components[Index]);
    if Result <> nil then
      Exit;
  end;
end;

function MethodWith(AType: TRttiType; const AName: string; AParamCount: Integer): TRttiMethod;
var
  Method: TRttiMethod;
begin
  for Method in AType.GetMethods(AName) do
    if Length(Method.GetParameters) = AParamCount then
      Exit(Method);
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
  Info: TMemoryBasicInformation;
  ClassPtr: Pointer;
begin
  Result := False;
  if (APointer = nil) or (VirtualQuery(APointer, Info, SizeOf(Info)) = 0) or (Info.State <> MEM_COMMIT) then
    Exit;
  ClassPtr := PPointer(APointer)^;
  if (ClassPtr = nil) or (VirtualQuery(PByte(ClassPtr) + vmtSelfPtr, Info, SizeOf(Info)) = 0) or
    (Info.State <> MEM_COMMIT) then
    Exit;
  Result := PPointer(PByte(ClassPtr) + vmtSelfPtr)^ = ClassPtr;
end;

function InheritsFromName(AObject: TObject; const AClassName: string): Boolean;
var
  ClassType: TClass;
begin
  ClassType := AObject.ClassType;
  while ClassType <> nil do
  begin
    if SameText(ClassType.ClassName, AClassName) then
      Exit(True);
    ClassType := ClassType.ClassParent;
  end;
  Result := False;
end;

function PropValue(AContext: TRttiContext; AObject: TObject; const AName: string): TValue;
var
  Prop: TRttiProperty;
begin
  Prop := AContext.GetType(AObject.ClassType).GetProperty(AName);
  if (Prop = nil) or not Prop.IsReadable then
    Exit(TValue.Empty);
  Result := Prop.GetValue(AObject);
end;

function AsInt(const AValue: TValue): Integer;
begin
  if AValue.IsOrdinal then
    Result := AValue.AsOrdinal
  else
    Result := 0;
end;

{ TArgusMessageViewReader }

constructor TArgusMessageViewReader.Create(const AOnMessages: TArgusMessagesProc);
begin
  inherited Create;
  FOnMessages := AOnMessages;
end;

procedure TArgusMessageViewReader.ProjectStarted(const AProject: TArgusCompileProject);
begin
  FProject := AProject;
end;

procedure TArgusMessageViewReader.ReadSoon(ASucceeded: Boolean);
begin
  FSucceeded := ASucceeded;
  // Ein Lesen je Lauf: Gruppe und Projekte melden das Ende kurz nacheinander.
  if FPending then
    Exit;
  FPending := True;
  TThread.ForceQueue(nil,
    procedure
    var
      Messages: TArray<TArgusCompilerMessage>;
      Info: string;
    begin
      FPending := False;
      Messages := nil;
      try
        TArgusMessageView.Read(Messages, Info);
      except
        on E: Exception do
          Info := Info + '; ' + E.ClassName + ': ' + E.Message;
      end;
      if Assigned(FOnMessages) then
        FOnMessages(Messages, FProject, FSucceeded, Info);
    end);
end;

procedure TArgusMessageViewReader.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
  ReadSoon(ASucceeded);
end;

procedure TArgusMessageViewReader.ProjectFinished(const AProject: TArgusCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
begin
  FProject := AProject;
  ReadSoon(ASucceeded);
end;

{ TArgusMessageView }

class function TArgusMessageView.Read(out AMessages: TArray<TArgusCompilerMessage>; out AInfo: string): Boolean;
var
  Index, Count: Integer;
  Form: TForm;
  Tree: TComponent;
  Context: TRttiContext;
  TreeType: TRttiType;
  GetFirst, GetNext, GetNodeData: TRttiMethod;
  Node, Data: Pointer;
  Line: TObject;
  Message: TArgusCompilerMessage;
begin
  Result := False;
  AMessages := nil;
  Form := nil;
  for Index := 0 to Screen.FormCount - 1 do
    if SameText(Screen.Forms[Index].ClassName, FormClass) then
      Form := Screen.Forms[Index];
  if Form = nil then
  begin
    AInfo := FormClass + ' nicht gefunden';
    Exit;
  end;
  Tree := FindTree(Form);
  if Tree = nil then
  begin
    AInfo := 'Meldungsbaum nicht gefunden';
    Exit;
  end;
  Context := TRttiContext.Create;
  try
    TreeType := Context.GetType(Tree.ClassType);
    // Je nach Version mit oder ohne ConsiderChildrenAbove.
    GetFirst := MethodWith(TreeType, 'GetFirst', 1);
    if GetFirst = nil then
      GetFirst := MethodWith(TreeType, 'GetFirst', 0);
    GetNext := MethodWith(TreeType, 'GetNext', 2);
    if GetNext = nil then
      GetNext := MethodWith(TreeType, 'GetNext', 1);
    GetNodeData := MethodWith(TreeType, 'GetNodeData', 1);
    if (GetFirst = nil) or (GetNext = nil) or (GetNodeData = nil) then
    begin
      AInfo := Format('%s: über RTTI nicht erreichbar (GetFirst %s, GetNext %s, GetNodeData %s)', [Tree.ClassName,
        BoolToStr(GetFirst <> nil, True), BoolToStr(GetNext <> nil, True), BoolToStr(GetNodeData <> nil, True)]);
      Exit;
    end;
    if Length(GetFirst.GetParameters) = 1 then
      Node := GetFirst.Invoke(Tree, [False]).AsType<Pointer>
    else
      Node := GetFirst.Invoke(Tree, []).AsType<Pointer>;
    Count := 0;
    while (Node <> nil) and (Count < MaxNodes) do
    begin
      Data := GetNodeData.Invoke(Tree, [PointerArg(GetNodeData.GetParameters[0], Node)]).AsType<Pointer>;
      if (Data <> nil) and LooksLikeObject(PPointer(Data)^) then
      begin
        Line := TObject(PPointer(Data)^);
        if InheritsFromName(Line, MessageLineClass) then
        begin
          Message := TArgusCompilerMessages.FromIde(PropValue(Context, Line, 'Kind').ToString,
            PropValue(Context, Line, 'Message').ToString, PropValue(Context, Line, 'FileName').ToString,
            AsInt(PropValue(Context, Line, 'Line')), AsInt(PropValue(Context, Line, 'Column')));
          if Message.Severity <> TArgusCompilerSeverity.Info then
            AMessages := AMessages + [Message];
        end;
      end;
      if Length(GetNext.GetParameters) = 2 then
        Node := GetNext.Invoke(Tree, [PointerArg(GetNext.GetParameters[0], Node), False]).AsType<Pointer>
      else
        Node := GetNext.Invoke(Tree, [PointerArg(GetNext.GetParameters[0], Node)]).AsType<Pointer>;
      Inc(Count);
    end;
    AInfo := Format('%d Knoten, %d Meldungen', [Count, Length(AMessages)]);
    Result := True;
  finally
    Context.Free;
  end;
end;

end.