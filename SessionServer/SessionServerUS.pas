unit SessionServerUS;

interface

uses
  Logger,
  StdIni,

  Ora,
  OraObjects,
  Data.DB,
  OraSmart,
  MyOraLib,

  ODBFiles2,

  WorldDataCode,
  WorldLegends,

  IMB3NativeClient,

  imb4,
  WorldTilerConsts,
  CommandQueue,
  TimerPool,

  SessionServerLib,
  SessionServerGIS,

  Vcl.graphics, // TPicture

  GisDefs, GisCsSystems, GisLayerSHP, GisLayerVector,

  System.JSON,
  System.Math,
  System.Classes,
  System.SysUtils,
  System.Generics.Defaults,
  System.Generics.Collections;

type
  TUSLayer = class; // forward

  TIMBEventEntryArray = array of TIMBEventEntry;

  TMetaLayerEntry = record
    valid: Boolean;
    // fields
    OBJECT_ID: Integer;
    LAYER_TYPE: Integer;
    LAYER_TABLE: string;
    LEGEND_FILE: string;
    LEGEND_DESC: string;
    VALUE_EXPR: string;
    VALUE_NODATA: Double;
    JOINCONDITION: string;
    TEXTURE_FILE: string;
    TEXTURE_EXPR: string;
    ROW_START: Integer;
    ROW_SIZE: Integer;
    COL_START: Integer;
    COL_SIZE: Integer;
    ROW_FIELD: string;
    COL_FIELD: string;
    IS_CELL_BASED: Boolean;
    MXR: Double;
    MXC: Double;
    MXT: Double;
    MYR: Double;
    MYC: Double;
    MYT: Double;
    IMB_EVENTCLASS: string;
    // added for web interface
    domain: string;
    description: string;
    diffRange: Double;
    objectType: string;
    geometryType: string;
    _published: Integer;
    // indirect
    legendAVL: string;
    odbList: TODBList;
  public
    procedure ReadFromQueryRow(aQuery: TOraQuery);
    function BaseTable(const aTablePrefix:string): string;
    function BaseTableNoPrefix: string;
    function BuildJoin(const aTablePrefix: string; out aShapePrefix: string): string;
    function SQLQuery(const aTablePrefix:string; xMin: Integer=0; yMin: Integer=0; xMax: Integer=-1; yMax: Integer=-1): string;
    function SQLQueryNew(const aTablePrefix:string): string;
    function SQLQueryChange(const aTablePrefix:string): string;
    function autoDiffRange: Double;
    function BuildLegendJSON(aLegendFormat: TLegendFormat): string;
    function CreateUSLayer(aScenario: TScenario; const aTablePrefix: string; const aConnectString: string;
      const aDataEvent: array of TIMBEventEntry; aSourceProjection: TGIS_CSProjectedCoordinateSystem; const aDomain, aName: string): TUSLayer;
  end;

  TMetaLayer = TDictionary<Integer, TMetaLayerEntry>;

  // extra fields in meta_scenarios
    // published, null,0,1,2
  // extra fields in meta_layer
  	// domain, string
    // published, null,0,1,2,
    // diffRange, double
    // title, string, null, ".."
    // description, string, null, ".."

  TUSRoadIC = class(TGeometryLayerObject)
  constructor Create(aLayer: TLayer; const aID: TWDID; aGeometry: TWDGeometry; aValue, aTexture: Double);
  protected
    fTexture: Double;
  public
    function Encode: TByteBuffer; override;
  public
    property texture: Double read fTexture;
  end;

  TUSRoadICLR = class(TGeometryLayerObject)
  constructor Create(aLayer: TLayer; const aID: TWDID; aGeometry: TWDGeometry; aValue, aValue2, aTexture, aTexture2: Double);
  protected
    fValue2: Double;
    fTexture: Double;
    fTexture2: Double;
  public
    function Encode: TByteBuffer; override;
  public
    property value2: Double read fValue2 write fValue2;
    property texture: Double read fTexture write fTexture;
    property texture2: Double read fTexture2 write fTexture2;
  end;

  TUSPOI = class
  constructor Create(aID: Integer; aPicture: TPicture);
  destructor Destroy; override;
  protected
    fID: Integer;
    fPicture: TPicture; // owns
  public
    property ID: Integer read fID;
    property picture: TPicture read fPicture;
    // todo: encode ?
  end;

  TUSLayer = class(TLayer)
  constructor Create(aScenario: TScenario; const aDomain, aID, aName, aDescription: string;
    aDefaultLoad: Boolean; const aObjectTypes, aGeometryType: string; aLayerType: Integer; aDiffRange: Double;
    const aConnectString, aNewQuery, aChangeQuery: string; const aDataEvent: array of TIMBEventEntry;
    aSourceProjection: TGIS_CSProjectedCoordinateSystem; aPalette: TWDPalette; aBasicLayer: Boolean=False);
  destructor Destroy; override;
  protected
    fConnectString: string;
    fOraSession: TOraSession;
    fLayerType: Integer;
    fNewPoiCatID: Integer;
    fPoiCategories: TObjectDictionary<string, TUSPOI>;
    fPalette: TWDPalette;
    fSourceProjection: TGIS_CSProjectedCoordinateSystem; // ref
    fDataEvents: array of TIMBEventEntry;
    fNewQuery: TOraQuery;
    fChangeQuery: TOraQuery;

    function UpdateObject(aQuery: TOraQuery; const oid: TWDID; aObject: TLayerObject): TLayerObject;
    function newObjectQuery(const oid: TWDID): string;
    function changeObjectQuery(const oid: TWDID): string;
    procedure handleChangeObject(aAction, aObjectID: Integer; const aObjectName, aAttribute: string); stdcall;
  public
    procedure ReadObjects(aSender: TObject);
    procedure RegisterLayer; override;
    procedure RegisterSlice; override;
    function SliceType: Integer; override;
  end;

  TUSScenario = class(TScenario)
  constructor Create(aProject: TProject; const aID, aName, aDescription: string; aAddBasicLayers: Boolean; aMapView: TMapView; aIMBConnection: TIMBConnection; const aTablePrefix: string);
  private
    fTableprefix: string;
    fIMBConnection: TIMBConnection; // ref
  public
    procedure ReadBasicData(); override;
  public
    // select objects
    function SelectObjects(aClient: TClient; const aType, aMode: string; const aSelectCategories: TArray<string>; aGeometry: TWDGeometry): string; overload; override;
    function SelectObjects(aClient: TClient; const aType, aMode: string; const aSelectCategories: TArray<string>; aX, aY, aRadius: Double): string; overload; override;
    function SelectObjects(aClient: TClient; const aType, aMode: string; const aSelectCategories: TArray<string>; aJSONQuery: TJSONArray): string; overload; override;
    function SelectObjects(aClient: TClient; const aType, aMode: string; const aSelectCategories: TArray<string>; const aSelectedIDs: TArray<string>): string; overload; override;
    // select object properties
    function selectObjectsProperties(aClient: TClient; const aSelectCategories, aSelectedObjects: TArray<string>): string; override;
  end;

  TUSDBScenario = class
  constructor Create(const aID, aName, aDescription, aParentID, aReferenceID, aTablePrefix, aIMBPrefix, aStatus: string; aPublished: Integer);
  private
    fID: string;
    fName: string;
    fDescription: string;
    fParentID: string;
    fParentname: string;
    fReferenceID: string;
    fReferenceName: string;
    fTablePrefix: string;
    fIMBPrefix: string;
    fStatus: string;
    fPublished: Integer;
  public
    procedure Relink(aUSDBScenarios: TObjectDictionary<string, TUSDBScenario>);
  public
    property ID: string read fID;
    property name: string read fName;
    property description: string read fDescription;
    property parentID: string read fParentID;
    property parentName: string read fParentName;
    property referenceID: string read fReferenceID;
    property referenceName: string read fReferenceName;
    property tablePrefix: string read fTablePrefix;
    property IMBPrefix: string read fIMBPrefix;
    property status: string read fStatus;
    property _published: Integer read fPublished;
  end;

  TUSProject = class(TProject)
  constructor Create(aSessionModel: TSessionModel; aConnection: TConnection; aIMB3Connection: TIMBConnection; const aProjectID, aProjectName, aTilerFQDN, aTilerStatusURL: string;
    aDBConnection: TCustomConnection; aMapView: TMapView; aPreLoadScenarios: Boolean; aMaxNearestObjectDistanceInMeters: Integer{; aSourceEPSG: Integer});
  destructor Destroy; override;
  private
    fUSDBScenarios: TObjectDictionary<string, TUSDBScenario>;
    fSourceProjection: TGIS_CSProjectedCoordinateSystem;
    fPreLoadScenarios: Boolean;
    fIMB3Connection: TIMBConnection;
    function getOraSession: TOraSession;
  protected
    procedure ReadScenarios;
    procedure ReadMeasures;
    function ReadScenario(const aID: string): TScenario; override;
  public
    procedure ReadBasicData(); override;
  public
    property OraSession: TOraSession read getOraSession;
    property sourceProjection: TGIS_CSProjectedCoordinateSystem read fSourceProjection;
  end;


function getUSMapView(aOraSession: TOraSession; const aDefault: TMapView): TMapView;
function getUSProjectID(aOraSession: TOraSession; const aDefault: string): string;
procedure setUSProjectID(aOraSession: TOraSession; const aValue: string);
function getUSCurrentPublishedScenarioID(aOraSession: TOraSession; aDefault: Integer): Integer;

function Left(const s: string; n: Integer): string;
function Right(const s: string; n: Integer): string;
function StartsWith(const s, LeftStr: string): Boolean;
procedure SplitAt(const s: string; i: Integer; var LeftStr, RightStr: string);

function ReadMetaLayer(aSession: TOraSession; const aTablePrefix: string; aMetaLayer: TMetaLayer): Boolean;

function CreateWDGeometryFromSDOShape(aQuery: TOraQuery; const aFieldName: string): TWDGeometry;
function CreateWDGeometryPointFromSDOShape(aQuery: TOraQuery; const aFieldName: string): TWDGeometryPoint;

function ConnectStringFromSession(aOraSession: TOraSession): string;
function ConnectToUSProject(const aConnectString, aProjectID: string; out aMapView: TMapView): TOraSession;

implementation

function ConnectStringFromSession(aOraSession: TOraSession): string;
begin
  with aOraSession
  do Result := userName+'/'+password+'@'+server;
end;

function ConnectToUSProject(const aConnectString, aProjectID: string; out aMapView: TMapView): TOraSession;
var
  dbConnection: TOraSession;
begin
  dbConnection := TOraSession.Create(nil);
  dbConnection.ConnectString := aConnectString;
  dbConnection.Open;
  setUSProjectID(dbConnection, aProjectID); // store project id in database
  aMapView := getUSMapView(dbConnection as TOraSession, TMapView.Create(52.08606, 5.17689, 11));
  Result := dbConnection;
end;

function defaultTablePrefix(aOraSession: TOraSession): string;
begin

end;

function Left(const s: string; n: Integer): string;
begin
  if n > 0 then
  begin
    if n >= Length(s)
    then Result := s
    else Result := Copy(s, 1, n);
  end
  else Result := '';
end;

function Right(const s: string; n: Integer): string;
begin
  if n > 0 then
  begin
    if n >= Length(s)
    then Result := s
    else Result := Copy(s, Length(s) - n + 1, n);
  end
  else Result := '';
end;

function StartsWith(const s, LeftStr: string): Boolean;
begin
  Result := AnsiCompareText(Left(s, Length(LeftStr)), LeftStr) = 0;
end;

procedure SplitAt(const s: string; i: Integer; var LeftStr, RightStr: string);
begin
  LeftStr := Left(s, i - 1);
  RightStr := Right(s, Length(s) - i);
end;

function CreatePaletteFromODB(const aDescription: string; const odbList: TODBList; aIsNoDataTransparent: Boolean): TWDPalette;
var
  entries: TPaletteDiscreteEntryArray;
  noDataColor: TAlphaRGBPixel;
  i: Integer;
  p: TDiscretePaletteEntry;
begin
  noDataColor := 0 ; // transparent // TAlphaColors.black and not TAlphaColors.Alpha;
  setLength(entries, 0);
  for i := 0 to Length(odbList)-1 do
  begin
    if not odbList[i].IsNoData then
    begin
      p.colors := TGeoColors.Create(odbList[i].Color);
      p.minValue := odbList[i].Min;
      p.maxValue := odbList[i].Max;
      p.description := odbList[i].Description;
      setLength(entries, length(entries)+1);
      entries[length(entries)-1] := p;
    end
    else
    begin
      if aIsNoDataTransparent
      then noDataColor := 0
      else noDataColor := odbList[i].Color;
    end;
  end;
  Result := TDiscretePalette.Create(aDescription, entries, TGeoColors.Create(noDataColor));
end;

function ReadMetaLayer(aSession: TOraSession; const aTablePrefix: string; aMetaLayer: TMetaLayer): Boolean;
var
  query: TOraQuery;
  metaLayerEntry: TMetaLayerEntry;
begin
  query := TOraQuery.Create(nil);
  try
    query.Session := aSession;
    query.SQL.Text := 'SELECT * FROM '+aTablePrefix+'META_LAYER';
    query.Open;
    while not query.Eof do
    begin
      // default
      metaLayerEntry.ReadFromQueryRow(query);
      aMetaLayer.Add(metaLayerEntry.OBJECT_ID, metaLayerEntry);
      query.Next;
    end;
    Result := True;
  finally
    query.Free;
  end;
end;

function TMetaLayerEntry.BaseTableNoPrefix: string;
var
  p: Integer;
  t1: string;
  t2: string;
begin
  p := Pos('!', LAYER_TABLE);
  if p>0 then
  begin
    SplitAt(LAYER_TABLE, p, t1, t2);
    Result := t1;
  end
  else
  begin
    p := Pos('*', LAYER_TABLE);
    if p>0 then
    begin
      t1 := Copy(LAYER_TABLE, 1, p-1);
      Result := t1;
    end
    else
    begin // single table?
      if StartsWith(LAYER_TABLE, 'GENE_ROAD_') then
      begin
        t1 := 'GENE_ROAD';
        Result := t1;
      end
      else
      begin
        if StartsWith(LAYER_TABLE, 'GENE_BUILDING_') then
        begin
          t1 := 'GENE_BUILDING';
          Result := t1;
        end
        else
        begin
          t1 := LAYER_TABLE;
          Result := t1;
        end;
      end;
    end;
  end;
end;

function TMetaLayerEntry.BaseTable(const aTablePrefix:string): string;
var
  p: Integer;
  t1: string;
  t2: string;
begin
  p := Pos('!', LAYER_TABLE);
  if p>0 then
  begin
    SplitAt(LAYER_TABLE, p, t1, t2);
    Result := aTablePrefix+t1;
  end
  else
  begin
    p := Pos('*', LAYER_TABLE);
    if p>0 then
    begin
      t1 := Copy(LAYER_TABLE, 1, p-1);
      Result := aTablePrefix+t1;
    end
    else
    begin // single table?
      if StartsWith(LAYER_TABLE, 'GENE_ROAD_') then
      begin
        t1 := 'GENE_ROAD';
        Result := aTablePrefix+t1;
      end
      else
      begin
        if StartsWith(LAYER_TABLE, 'GENE_BUILDING_') then
        begin
          t1 := 'GENE_BUILDING';
          Result := aTablePrefix+t1;
        end
        else
        begin
          t1 := LAYER_TABLE;
          Result := aTablePrefix+t1;
        end;
      end;
    end;
  end;
end;

function TMetaLayerEntry.BuildJoin(const aTablePrefix: string; out aShapePrefix: string): string;
var
  p: Integer;
  t1: string;
  t2: string;
begin
  aShapePrefix := '';
  p := Pos('!', LAYER_TABLE);
  if p>0 then
  begin
    SplitAt(LAYER_TABLE, p, t1, t2);
    Result := aTablePrefix+t1+' t1 JOIN '+aTablePrefix+t2+' t2 ON t1.OBJECT_ID=t2.OBJECT_ID';
    aShapePrefix := 't1.';
  end
  else
  begin
    p := Pos('*', LAYER_TABLE);
    if p>0 then
    begin
      t1 := Copy(LAYER_TABLE, 1, p-1);
      t2 := LAYER_TABLE;
      Delete(t2, p, 1);
      Result := aTablePrefix+t1+' t1 JOIN '+aTablePrefix+t2+' t2 ON t1.OBJECT_ID=t2.OBJECT_ID';
      aShapePrefix := 't1.';
    end
    else
    begin // single table?
      if StartsWith(LAYER_TABLE, 'GENE_ROAD_') then
      begin
        t1 := 'GENE_ROAD';
        t2 := LAYER_TABLE;
        Result := aTablePrefix+t1+' t1 JOIN '+aTablePrefix+t2+' t2 ON t1.OBJECT_ID=t2.OBJECT_ID';
        aShapePrefix := 't1.';
      end
      else
      begin
        if StartsWith(LAYER_TABLE, 'GENE_BUILDING_') then
        begin
          t1 := 'GENE_BUILDING';
          t2 := LAYER_TABLE;
          Result := aTablePrefix+t1+' t1 JOIN '+aTablePrefix+t2+' t2 ON t1.OBJECT_ID=t2.OBJECT_ID';
          aShapePrefix := 't1.';
        end
        else
        begin
          t1 := LAYER_TABLE;
          //t2 := '';
          Result := aTablePrefix+t1+' t1';
          aShapePrefix := 't1.';
        end;
      end;
    end;
  end;
end;

function TMetaLayerEntry.BuildLegendJSON(aLegendFormat: TLegendFormat): string;
var
  i: Integer;
begin
  Result := '';
  case aLegendFormat of
    lfVertical:
      begin
        for i := 0 to length(odbList)-1 do
        begin
          if not odbList[i].IsNoData then
          begin
            if Result<>''
            then Result := Result+',';
            Result := Result+'{"'+odbList[i].Description+'":{"fillColor":"'+ColorToJSON(odbList[i].Color)+'"}}';
          end;
        end;
        Result := '"grid":{"title":"'+FormatLegendDescription(LEGEND_DESC)+'","labels":['+Result+']}';;
      end;
    lfHorizontal:
      begin
        for i := 0 to length(odbList)-1 do
        begin
          if not odbList[i].IsNoData then
          begin
            if Result<>''
            then Result := Result+',';
            Result := Result+'"'+odbList[i].Description+'":{"fillColor":"'+ColorToJSON(odbList[i].Color)+'"}}';
          end;
        end;
        Result := '"grid2":{"title":"'+FormatLegendDescription(LEGEND_DESC)+'","labels":[{'+Result+'}]}';;
      end;
  end;
end;


function TMetaLayerEntry.CreateUSLayer(aScenario: TScenario; const aTablePrefix: string; const aConnectString: string;
  const aDataEvent: array of TIMBEventEntry; aSourceProjection: TGIS_CSProjectedCoordinateSystem; const aDomain, aName: string): TUSLayer;

  function defaultValue(aValue, aDefault: Double): Double; overload;
  begin
    if not IsNaN(aValue)
    then Result := aValue
    else Result := aDefault;
  end;

  function defaultValue(const aValue, aDefault: string): string; overload;
  begin
    if aValue<>''
    then Result := aValue
    else Result := aDefault;
  end;

var
  objectTypes: string;
begin
  Result := nil; // sentinel
  case LAYER_TYPE mod 100 of // i+100 image layer version same as i but ignored by US3D
    1:
      begin
        objectTypes := '"receptor"';
        geometryType := 'Point';
        diffRange := defaultValue(diffRange, autoDiffRange*0.3);
      end;
    2:
      begin
        objectTypes := '"grid"';
        geometryType := 'MultiPolygon'; // todo: ?
        diffRange := defaultValue(diffRange, autoDiffRange*0.3);
      end;
    3, 8:
      begin
        objectTypes := '"building"'; // 3 buildings, 8 RS buildings
        geometryType := 'MultiPolygon';
        diffRange := defaultValue(diffRange, autoDiffRange*0.3);
      end;
    4,    // road color (VALUE_EXPR)
    5:    // road color (VALUE_EXPR) and width (TEXTURE_EXPR)
      begin
        objectTypes := '"road"';
        geometryType := 'LineString';
        diffRange := defaultValue(diffRange, autoDiffRange*0.3);
      end;
    9:    // enrg color (VALUE_EXPR) and width (TEXTURE_EXPR)
      begin
        objectTypes := '"energy"';
        geometryType := 'LineString';
        diffRange := defaultValue(diffRange, autoDiffRange*0.3);
      end;
    11:
      begin
        objectTypes := '"location"';
        geometryType := 'Point';
        diffRange := diffRange; // todo:
      end;
    21:
      begin
        objectTypes := '"poi"';
        geometryType := 'Point';
        diffRange := diffRange; // todo:
      end;
  else
    // 31 vector layer ?
    objectTypes := '';
    geometryType := '';
    diffRange := diffRange;
  end;
  if geometryType<>'' then
  begin
    Result := TUSLayer.Create(aScenario,
      aDomain,
      OBJECT_ID.ToString, // id
      aName,
      LEGEND_DESC.Replace('~~', '-').replace('\', '-'), // description
      false, //false, // todo: default load
      objectTypes, geometryType,
      LAYER_TYPE mod 100,
      diffRange,
      aConnectString,
      SQLQueryNew(aTablePrefix),
      SQLQueryChange(aTablePrefix),
      aDataEvent,
      aSourceProjection,
      CreatePaletteFromODB(LEGEND_DESC, odbList, True));
    Result.fLegendJSON := BuildLegendJSON(lfVertical);
    Result.query := SQLQuery(aTableprefix);
  end;
end;

procedure TMetaLayerEntry.ReadFromQueryRow(aQuery: TOraQuery);

  function StringField(const aFieldName: string; const aDefaultValue: string=''): string;
  var
    F: TField;
  begin
    F := aQuery.FieldByName(aFieldName);
    if Assigned(F) and not F.IsNull
    then Result := F.AsString
    else Result := aDefaultValue;
  end;

  function IntField(const aFieldName: string; aDefaultValue: Integer=0): Integer;
  var
    F: TField;
  begin
    F := aQuery.FieldByName(aFieldName);
    if Assigned(F) and not F.IsNull
    then Result := F.AsInteger
    else Result := aDefaultValue;
  end;

  function DoubleField(const aFieldName: string; aDefaultValue: Double=NaN): Double;
  var
    F: TField;
  begin
    F := aQuery.FieldByName(aFieldName);
    if Assigned(F) and not F.IsNull
    then Result := F.AsFloat
    else Result := aDefaultValue;
  end;

var
  sl: TStringList;
begin
  // default
  OBJECT_ID := IntField('OBJECT_ID');
  LAYER_TYPE := IntField('LAYER_TYPE');
  LAYER_TABLE := StringField('LAYER_TABLE');
  LEGEND_FILE := StringField('LEGEND_FILE');
  LEGEND_DESC := StringField('LEGEND_DESC');
  VALUE_EXPR := StringField('VALUE_EXPR');
  VALUE_NODATA := DoubleField('VALUE_NODATA');
  JOINCONDITION := StringField('JOINCONDITION');
  TEXTURE_FILE := StringField('TEXTURE_FILE');
  TEXTURE_EXPR := StringField('TEXTURE_EXPR');
  ROW_START := IntField('ROW_START');
  ROW_SIZE := IntField('ROW_SIZE');
  COL_START := IntField('COL_START');
  COL_SIZE := IntField('COL_SIZE');
  ROW_FIELD := StringField('ROW_FIELD');
  COL_FIELD := StringField('COL_FIELD');
  IS_CELL_BASED := IntField('IS_CELL_BASED')=1;
  MXR := DoubleField('MXR');
  MXC := DoubleField('MXC');
  MXT := DoubleField('MXT');
  MYR := DoubleField('MYR');
  MYC := DoubleField('MYC');
  MYT := DoubleField('MYT');
  IMB_EVENTCLASS := StringField('IMB_EVENTCLASS');

  // added for web interface
  domain := StringField('DOMAIN');
  description := StringField('DESCRIPTION');
  diffRange := DoubleField('DIFFRANGE');
  objectType := StringField('OBJECTTYPE');
  geometryType := StringField('GEOMETRYTYPE');
  _published := IntField('PUBLISHED', 1);

  {
  ALTER TABLE VXX#META_LAYER
  ADD (DOMAIN VARCHAR2(50), DESCRIPTION VARCHAR2(150), DIFFRANGE NUMBER, OBJECTTYPE VARCHAR2(50), GEOMETRYTYPE VARCHAR2(50), PUBLISHED INTEGER);

  UPDATE V21#META_LAYER SET DIFFRANGE = 2 WHERE object_id in (142,52,53,54,55,153,3,4,28,32,141,56);
  }

  LegendAVL := '';
  setLength(odbList, 0);
  if LEGEND_FILE<>'' then
  begin
    sl := TStringList.Create;
    try
      if SaveBlobToStrings(aQuery.Session, 'VI3D_MODEL', 'PATH', LEGEND_FILE, 'BINFILE', sl) then
      begin
        LegendAVL := sl.Text;
        odbList := ODBFileToODBList(sl);
      end;
    finally
      sl.Free;
    end;
  end;
end;

function TMetaLayerEntry.autoDiffRange: Double;
var
  odb: TODBRecord;
  values: TList<double>;

  procedure addValue(aValue: Double);
  begin
    if not IsNaN(aValue)
    then values.Add(aValue);
  end;

begin
  values := TList<double>.Create;
  try
    for odb in odbList do
    begin
      addValue(odb.Min);
      addValue(odb.Max);
    end;
    values.Sort;
    // remove first and last value to remove large ranges on the edge off legends
    values.Delete(0);
    values.Delete(values.Count-1);
    // use difference highest-lowest/aFactor
    Result := Abs(values[values.count-1]-values[0]);
  finally
    values.Free;
  end;
end;

function TMetaLayerEntry.SQLQuery(const aTablePrefix:string; xMin, yMin, xMax, yMax: Integer): string;
var
  join: string;
  ShapePrefix: string;
  cellIndexFiltering: Boolean;
begin
  join := BuildJoin(aTablePrefix, ShapePrefix);
  case LAYER_TYPE mod 100 of
    2:
      begin
        cellIndexFiltering :=  (xMin<=xMax) and (yMin<=yMax);
        join := JOINCONDITION;
        if (join<>'') and cellIndexFiltering
        then join := join+' AND ';
        Result :=
            'SELECT '+
              COL_FIELD+', '+
              ROW_FIELD+', '+
              VALUE_EXPR+' '+
            'FROM '+aTablePrefix+LAYER_TABLE;
        if (join<>'') or cellIndexFiltering then
        begin
          Result := Result+' '+
            'WHERE '+
              join;
          if cellIndexFiltering
          then Result := Result+' '+
              IntToStr(xMin)+'<='+COL_FIELD+' AND '+COL_FIELD+'<='+IntToStr(xMax)+' AND '+
              IntToStr(yMin)+'<='+ROW_FIELD+' AND '+ROW_FIELD+'<='+IntToStr(yMax);
        end;
        Result := Result+' '+
            'ORDER BY '+ROW_FIELD+','+COL_FIELD;
      end;
    4:
      begin
        Result :=
          'SELECT '+
            ShapePrefix+'OBJECT_ID, '+
            VALUE_EXPR+' AS VALUE, '+
            ShapePrefix+'SHAPE '+
          'FROM '+join;
        if JOINCONDITION<>''
        then Result := Result+' '+
          'WHERE '+JOINCONDITION;
      end;
    5, 9:
      begin
        Result :=
          'SELECT '+
            ShapePrefix+'OBJECT_ID, '+
            VALUE_EXPR+','+
            TEXTURE_EXPR+','+
            ShapePrefix+'SHAPE '+
          'FROM '+join;
        if JOINCONDITION<>''
        then Result := Result+' '+
          'WHERE '+JOINCONDITION;
      end;
    21:
      begin
        Result :=
          'SELECT '+
            ShapePrefix+'OBJECT_ID, '+
            ShapePrefix+'shape.sdo_point.x, '+
            ShapePrefix+'shape.sdo_point.y, '+
            ShapePrefix+'poiType, '+
            ShapePrefix+'category '+
          'FROM '+join;
        if JOINCONDITION<>''
        then Result := Result+' '+
          'WHERE '+JOINCONDITION;
      end;
  else
    Result :=
      'SELECT '+
        ShapePrefix+'OBJECT_ID, '+
        VALUE_EXPR+' AS VALUE, '+
        ShapePrefix+'SHAPE '+
      'FROM '+join;
    if JOINCONDITION<>''
    then Result := Result+' '+
      'WHERE '+JOINCONDITION;
  end;
end;

function TMetaLayerEntry.SQLQueryChange(const aTablePrefix: string): string;
var
  join: string;
  ShapePrefix: string;
begin
  join := BuildJoin(aTablePrefix, ShapePrefix);
  case LAYER_TYPE mod 100 of
    2:
      begin
        Result := ''; // todo: can this work?
      end;
    4:
      begin
        Result :=
          'SELECT '+
            VALUE_EXPR+' AS VALUE '+
          'FROM '+join+' '+
          'WHERE '+ShapePrefix+'OBJECT_ID=:OBJECT_ID';
        if JOINCONDITION<>''
        then Result := Result+' AND '+
          JOINCONDITION;
      end;
    5, 9:
      begin
        Result :=
          'SELECT '+
            VALUE_EXPR+','+
            TEXTURE_EXPR+' '+
          'FROM '+join+' '+
          'WHERE '+ShapePrefix+'OBJECT_ID=:OBJECT_ID';
        if JOINCONDITION<>''
        then Result := Result+' AND '+
          JOINCONDITION;
      end;
    21:
      begin
        Result := ''; // todo: can this work?
      end;
  else
    Result :=
      'SELECT '+
        VALUE_EXPR+' AS VALUE '+
      'FROM '+join+' '+
      'WHERE '+ShapePrefix+'OBJECT_ID=:OBJECT_ID';
    if JOINCONDITION<>''
    then Result := Result+' AND '+
      JOINCONDITION;
  end;
end;

function TMetaLayerEntry.SQLQueryNew(const aTablePrefix: string): string;
var
  join: string;
  ShapePrefix: string;
begin
  join := BuildJoin(aTablePrefix, ShapePrefix);
  case LAYER_TYPE mod 100 of
    2:
      begin
        Result := ''; // todo: can this work?
      end;
    4:
      begin
        Result :=
          'SELECT '+
            VALUE_EXPR+' AS VALUE, '+
            ShapePrefix+'SHAPE '+
          'FROM '+join+' '+
          'WHERE '+ShapePrefix+'OBJECT_ID=:OBJECT_ID';
        if JOINCONDITION<>''
        then Result := Result+' AND '+
          JOINCONDITION;
      end;
    5, 9:
      begin
        Result :=
          'SELECT '+
            VALUE_EXPR+','+
            TEXTURE_EXPR+','+
            ShapePrefix+'SHAPE '+
          'FROM '+join+' '+
          'WHERE '+ShapePrefix+'OBJECT_ID=:OBJECT_ID';
        if JOINCONDITION<>''
        then Result := Result+' AND '+
          JOINCONDITION;
      end;
    21:
      begin
        Result :=
          'SELECT '+
            ShapePrefix+'shape.sdo_point.x, '+
            ShapePrefix+'shape.sdo_point.y, '+
            ShapePrefix+'poiType, '+
            ShapePrefix+'category '+
          'FROM '+join+' '+
          'WHERE '+ShapePrefix+'OBJECT_ID=:OBJECT_ID';
        if JOINCONDITION<>''
        then Result := Result+' AND '+
          JOINCONDITION;
      end;
  else
    Result :=
      'SELECT '+
        VALUE_EXPR+' AS VALUE, '+
        ShapePrefix+'SHAPE '+
      'FROM '+join+' '+
      'WHERE '+ShapePrefix+'OBJECT_ID=:OBJECT_ID';
    if JOINCONDITION<>''
    then Result := Result+' AND '+
      JOINCONDITION;
  end;
end;

function CreateWDGeometryFromSDOShape(aQuery: TOraQuery; const aFieldName: string): TWDGeometry;
// https://docs.oracle.com/cd/B19306_01/appdev.102/b14255/sdo_objrelschema.htm
var
  Geometry: TOraObject;
  Ordinates: TOraArray;
  ElemInfo: TOraArray;
  GType: Integer;
  NParts: Integer;
  PartNo: Integer;
  PartSize: Integer;
  x1,y1{,z1}: double;
  i: Integer;
  pnt: Integer;
begin
  // create WDGeometry as function result
  Result := TWDGeometry.Create;
  // read SDO geometry
  Geometry := aQuery.GetObject(aFieldName);
  GType := Geometry.AttrAsInteger['SDO_GTYPE'];
  Ordinates := Geometry.AttrAsArray['SDO_ORDINATES'];
  ElemInfo := Geometry.AttrAsArray['SDO_ELEM_INFO'];
  // convert SDO geometry to WDGeometry
  case Gtype of
    2007: // 2D MULTIPOLYGON
      begin
        NParts := ElemInfo.Size div 3;
        for PartNo := 0 to NParts-1 do
        begin
          Result.AddPart;
          i := ElemInfo.ItemAsInteger[PartNo*3]-1; // convert 1-based index to 0-based (TOraArray)
          if PartNo < NParts-1
          then PartSize := ElemInfo.ItemAsInteger[(PartNo+1)*3] - i
          else PartSize := Ordinates.Size - i;
          PartSize := PartSize div 2; // 2 ordinates per co-ordinate
          for pnt := 0 to PartSize-1 do
          begin
            Result.AddPoint(Ordinates.ItemAsFloat[i], Ordinates.ItemAsFloat[i + 1], NaN);
            Inc(i, 2);
          end;
        end;

      end;
    2003: // 2D POLYGON
      begin
        NParts := ElemInfo.Size div 3;
        for PartNo := 0 to NParts-1 do
        begin
          Result.AddPart;
          i := ElemInfo.ItemAsInteger[PartNo*3]-1; // convert 1-based index to 0-based (TOraArray)
          if PartNo < NParts-1
          then PartSize := ElemInfo.ItemAsInteger[(PartNo+1)*3] - i
          else PartSize := Ordinates.Size - i;
          PartSize := PartSize div 2; // 2 ordinates per co-ordinate
          for pnt := 0 to PartSize-1 do
          begin
            Result.AddPoint(Ordinates.ItemAsFloat[i], Ordinates.ItemAsFloat[i + 1], NaN);
            Inc(i, 2);
          end;
        end;
      end;
    2002: // 2D LINE
      begin
        for pnt := 0 to (Ordinates.Size div 2)-1 do
        begin
          Result.AddPoint(Ordinates.ItemAsFloat[pnt*2], Ordinates.ItemAsFloat[pnt*2 + 1], NaN);
        end;
      end;
    2001: // 2D POINT
      begin
        x1:=Geometry.AttrAsFloat['SDO_POINT.X'];
        y1:=Geometry.AttrAsFloat['SDO_POINT.Y'];
        Result.AddPoint(x1, y1, NaN);
      end;
  end;
end;

function CreateWDGeometryPointFromSDOShape(aQuery: TOraQuery; const aFieldName: string): TWDGeometryPoint;
// https://docs.oracle.com/cd/B19306_01/appdev.102/b14255/sdo_objrelschema.htm
var
  Geometry: TOraObject;
  Ordinates: TOraArray;
  ElemInfo: TOraArray;
  GType: Integer;
  NParts: Integer;
  idx: Integer;
  StartIdx: Integer;
  EndIdx: Integer;
begin
  // create WDGeometryPoint as function result
  Result := TWDGeometryPoint.Create;
  // read SDO geometry
  Geometry := aQuery.GetObject(aFieldName);
  GType := Geometry.AttrAsInteger['SDO_GTYPE'];
  Ordinates := Geometry.AttrAsArray['SDO_ORDINATES'];
  ElemInfo := Geometry.AttrAsArray['SDO_ELEM_INFO'];
  // convert SDO geometry to WDGeometryPoint, use first point from SDO as value
  case Gtype of
    2007: // 2D MULTIPOLYGON
      begin
        if Ordinates.Size>=2 then
        begin
          Result.x := Ordinates.ItemAsFloat[0];
          Result.y := Ordinates.ItemAsFloat[1];
        end;
      end;
    2003: // 2D POLYGON
      begin
        Eleminfo.InsertItem(ElemInfo.Size); // prevent out of bounds
        ElemInfo.ItemAsInteger[ElemInfo.size-1]:=Ordinates.Size + 1;
        NParts := ElemInfo.Size div 3;
        if NParts>0 then
        begin
          idx := 0;
          StartIdx :=ElemInfo.ItemAsInteger[idx*3];
          EndIdx   :=ElemInfo.ItemAsInteger[(idx*3)+3] -2 ;
          if EndIdx > StartIdx then
          begin
            Result.x := ordinates.itemasfloat[EndIdx-1];
            Result.y := ordinates.itemasfloat[EndIdx];
          end;
        end;
      end;
    2002: // 2D LINE
      begin
        if Ordinates.Size>=2 then
        begin
          Result.x := Ordinates.ItemAsFloat[0];
          Result.y := Ordinates.ItemAsFloat[1];
        end;
      end;
    2001: // 2D POINT
      begin
        Result.x := Geometry.AttrAsFloat['SDO_POINT.X'];
        Result.y := Geometry.AttrAsFloat['SDO_POINT.Y'];
      end;
  end;
end;

{ TUSRoadIC }

constructor TUSRoadIC.Create(aLayer: TLayer; const aID: TWDID; aGeometry: TWDGeometry; aValue, aTexture: Double);
begin
  inherited Create(aLayer, aID, aGeometry, aValue);
  fTexture := aTexture;
end;

function TUSRoadIC.Encode: TByteBuffer;
begin
  Result :=
    TByteBuffer.bb_tag_Double(icehTilerTexture, texture)+
    inherited Encode;
end;

{ TUSRoadICLR }

constructor TUSRoadICLR.Create(aLayer: TLayer; const aID: TWDID; aGeometry: TWDGeometry; aValue, aValue2, aTexture, aTexture2: Double);
begin
  inherited Create(aLayer, aID, aGeometry, aValue);
  fValue2 := aValue2;
  fTexture := aTexture;
  fTexture2 := aTexture2;
end;

function TUSRoadICLR.Encode: TByteBuffer;
begin
  Result :=
    TByteBuffer.bb_tag_Double(icehTilerTexture2, texture2)+
    TByteBuffer.bb_tag_Double(icehTilerTexture, texture)+
    TByteBuffer.bb_tag_Double(icehTilerValue2, value2)+
    inherited Encode;
end;

{ TUSPOI }

constructor TUSPOI.Create(aID: Integer; aPicture: TPicture);
begin
  inherited Create;
  fID := aID;
  fPicture := aPicture;
end;

destructor TUSPOI.Destroy;
begin
  FreeAndNil(fPicture);
  inherited Destroy;
end;

{ TUSLayer }

function TUSLayer.changeObjectQuery(const oid: TWDID): string;
begin
  // todo: implement
end;

constructor TUSLayer.Create(aScenario: TScenario; const aDomain, aID, aName, aDescription: string; aDefaultLoad: Boolean;
  const aObjectTypes, aGeometryType: string; aLayerType: Integer; aDiffRange: Double;
  const aConnectString, aNewQuery, aChangeQuery: string; const aDataEvent: array of TIMBEventEntry; aSourceProjection: TGIS_CSProjectedCoordinateSystem; aPalette: TWDPalette; aBasicLayer: Boolean);
var
  i: Integer;
begin
  fLayerType := aLayerType;
  fPoiCategories := TObjectDictionary<string, TUSPOI>.Create([doOwnsValues]);
  fNewPoiCatID := 0;
  fPalette := aPalette;
  fConnectString := aConnectString;

  fOraSession := TOraSession.Create(nil);
  fOraSession.ConnectString := fConnectString;
  fOraSession.Connect;

  fSourceProjection := aSourceProjection;

  if aNewQuery<>'' then
  begin
    fNewQuery := TOraQuery.Create(nil);
    fNewQuery.Session := fOraSession;
    fNewQuery.sql.Text := aNewQuery;
    fNewQuery.Prepare;
  end
  else fNewQuery := nil;

  if aChangeQuery<>'' then
  begin
    fChangeQuery := TOraQuery.Create(nil);
    fChangeQuery.Session := fOraSession;
    fChangeQuery.sql.Text := aChangeQuery;
    fChangeQuery.Prepare;
  end
  else  fChangeQuery := nil;

  inherited Create(aScenario, aDomain, aID, aName, aDescription, aDefaultLoad, aObjectTypes, aGeometryType, ltTile, True, aDiffRange, aBasicLayer);

  setLength(fDataEvents, length(aDataEvent));
  for i := 0 to length(aDataEvent)-1 do
  begin
    fDataEvents[i] := aDataEvent[i];
    fDataEvents[i].OnChangeObject := handleChangeObject;
  end;
end;

destructor TUSLayer.Destroy;
begin
  inherited;
  FreeAndNil(fPoiCategories);
  FreeAndNil(fPalette);
  FreeAndNil(fNewQuery);
  FreeAndNil(fChangeQuery);
  FreeAndNil(fOraSession);
end;

procedure TUSLayer.handleChangeObject(aAction, aObjectID: Integer; const aObjectName, aAttribute: string);
var
  wdid: TWDID;
  o: TLayerObject;
begin
  try
    wdid := AnsiString(aObjectID.ToString);
    if aAction=actionDelete then
    begin
      if FindObject(wdid, o)
      then RemoveObject(o);
    end
    else
    begin
      if aAction=actionNew then
      begin
        if not FindObject(wdid, o) then
        begin
          fNewQuery.ParamByName('OBJECT_ID').AsInteger := aObjectID;
          fNewQuery.Execute;
          if not fNewQuery.Eof
          then AddObject(UpdateObject(fNewQuery, wdid, nil))
          else Log.WriteLn('TUSLayer.handleChangeObject: no result on new object ('+aObjectID.toString+') query '+fNewQuery.SQL.Text, llWarning);
        end;
      end
      else if aAction=actionChange then
      begin
        if FindObject(wdid, o) then
        begin
          fChangeQuery.ParamByName('OBJECT_ID').AsInteger := aObjectID;
          fChangeQuery.Execute;
          if not fChangeQuery.Eof
          then UpdateObject(fChangeQuery, wdid, o)
          else Log.WriteLn('TUSLayer.handleChangeObject: no result on change object ('+aObjectID.toString+') query '+fChangeQuery.SQL.Text, llWarning);
        end;
      end;
    end;
  except
    on E: Exception
    do log.WriteLn('Exception in TUSLayer.handleChangeObject: '+e.Message, llError);
  end;
end;

function TUSLayer.newObjectQuery(const oid: TWDID): string;
begin
  // todo: implement
end;

function TUSLayer.UpdateObject(aQuery: TOraQuery; const oid: TWDID; aObject: TLayerObject): TLayerObject;

  function FieldFloatValueOrNaN(aField: TField): Double;
  begin
    if aField.IsNull
    then Result := NaN
    else Result := aField.AsFloat;
  end;

var
  value: double;
  geometryPoint: TWDGeometryPoint;
  geometry: TWDGeometry;
  value2: Double;
  texture: Double;
  texture2: Double;
begin
  Result := aObject;
  case fLayerType of
    1, 11:
      begin
        value := FieldFloatValueOrNaN(aQuery.FieldByName('VALUE'));
        if not Assigned(aObject) then
        begin
          geometryPoint := CreateWDGeometryPointFromSDOShape(aQuery, 'SHAPE');
          projectGeometryPoint(geometryPoint, fSourceProjection);
          Result := TGeometryPointLayerObject.Create(Self, oid, geometryPoint, value);
        end
        else (aObject as TGeometryPointLayerObject).value := value;
      end;
    4: // road (VALUE_EXPR)
      begin
        // unidirectional, not left and right
        value := FieldFloatValueOrNaN(aQuery.FieldByName('VALUE'));
        if not Assigned(aObject) then
        begin
          geometry := CreateWDGeometryFromSDOShape(aQuery, 'SHAPE');
          projectGeometry(geometry, fSourceProjection);
          Result := TGeometryLayerObject.Create(Self, oid, geometry, value);
        end
        else (aObject as TGeometryLayerObject).value := value;
      end;
    5,9: // road/energy (VALUE_EXPR) and width (TEXTURE_EXPR) left and right, for energy right will be null -> NaN
      begin
        // Left and right
        if not Assigned(aObject) then
        begin
          value := FieldFloatValueOrNaN(aQuery.Fields[1]);
          value2 := FieldFloatValueOrNaN(aQuery.Fields[2]);
          texture := FieldFloatValueOrNaN(aQuery.Fields[3]);
          texture2 := FieldFloatValueOrNaN(aQuery.Fields[4]);

          geometry := CreateWDGeometryFromSDOShape(aQuery, 'SHAPE');
          projectGeometry(geometry, fSourceProjection);
          Result := TUSRoadICLR.Create(Self, oid, geometry, value, value2, texture, texture2);
        end
        else
        begin
          value := FieldFloatValueOrNaN(aQuery.Fields[0]);
          value2 := FieldFloatValueOrNaN(aQuery.Fields[1]);
          texture := FieldFloatValueOrNaN(aQuery.Fields[2]);
          texture2 := FieldFloatValueOrNaN(aQuery.Fields[3]);

          (aObject as TUSRoadICLR).value := value;
          (aObject as TUSRoadICLR).value2 := value2;
          (aObject as TUSRoadICLR).texture := texture;
          (aObject as TUSRoadICLR).texture2 := texture2;
        end;
      end;
    21: // POI
      begin
        //
        (*
        geometryPoint := TWDGeometryPoint.Create;
        try
          geometryPoint.x := aQuery.Fields[1].AsFloat;
          geometryPoint.y := aQuery.Fields[2].AsFloat;
          // no projection, is already in lat/lon
          poiType := aQuery.Fields[3].AsString;
          poiCat := aQuery.Fields[4].AsString;
          if not fPoiCategories.TryGetValue(poicat+'_'+poiType, usPOI) then
          begin
            usPOI := TUSPOI.Create(fNewPoiCatID, TPicture.Create);
            fNewPoiCatID := fNewPoiCatID+1;
            try
              resourceFolder := ExtractFilePath(ParamStr(0));
              usPOI.picture.Graphic.LoadFromFile(resourceFolder+poicat+'_'+poiType+'.png');
            except
              on e: Exception
              do Log.WriteLn('Exception loading POI image '+resourceFolder+poicat+'_'+poiType+'.png', llError);
            end;
            // signal POI image to tiler
            //ImageToBytes(usPOI);
            //fTilerLayer.s
            {
            stream  := TBytesStream.Create;
            try
              usPOI.picture.Graphic.SaveToStream(stream);
              fOutputEvent.signalEvent(TByteBuffer.bb_tag_tbytes(icehTilerPOIImage, stream.Bytes)); // todo: check correct number of bytes
            finally
              stream.Free;
            end;
            }
          end;
        finally
          objects.Add(oid, TGeometryLayerPOIObject.Create(Self, oid, usPOI.ID, geometryPoint));
        end;
        *)
      end
  else
    value := FieldFloatValueOrNaN(aQuery.FieldByName('VALUE'));
    if not Assigned(aObject) then
    begin
      geometry := CreateWDGeometryFromSDOShape(aQuery, 'SHAPE');
      projectGeometry(geometry, fSourceProjection);
      Result := TGeometryLayerObject.Create(Self, oid, geometry, value);
    end
    else (aObject as TGeometryLayerObject).value := value;
  end;
end;

procedure TUSLayer.ReadObjects(aSender: TObject);

  function FieldFloatValueOrNaN(aField: TField): Double;
  begin
    if aField.IsNull
    then Result := NaN
    else Result := aField.AsFloat;
  end;

var
  oraSession: TOraSession;
  query: TOraQuery;
//  geometry: TWDGeometry;
  oid: RawByteString;
//  value: Double;
//  value2: Double;
//  texture: Double;
//  texture2: Double;
//  geometryPoint: TWDGeometryPoint;
//  poiType: string;
//  poiCat: string;
//  usPOI: TUSPOI;
//  resourceFolder: string;
//  stream: TBytesStream;
begin
  // register layer with tiler?
  // start query
  // decode objects and add to aLayer
  // send objects to tiler?

  // create new ora session because we are running in a different thread
  oraSession := TOraSession.Create(nil);
  try
    oraSession.connectString := fConnectString;
    oraSession.open;
    query := TOraQuery.Create(nil);
    try
      query.Session := oraSession;
      query.SQL.Text := fQuery; //.Replace('SELECT ', 'SELECT t1.OBJECT_ID,');
      query.Open;
      query.First;
      while not query.Eof do
      begin
        oid := AnsiString(query.Fields[0].AsInteger.ToString);
        objects.Add(oid, UpdateObject(query, oid, nil)); // always new object, no registering
        (*
        case fLayerType of
          1, 11:
            begin
              value := FieldFloatValueOrNaN(query.FieldByName('VALUE'));
              geometryPoint := CreateWDGeometryPointFromSDOShape(query, 'SHAPE');
              projectGeometryPoint(geometryPoint, fSourceProjection);
              objects.Add(oid, TGeometryPointLayerObject.Create(Self, oid, geometryPoint, value));
            end;
          4: // road (VALUE_EXPR)
            begin
              // unidirectional, not left and right
              value := FieldFloatValueOrNaN(query.Fields[1]);
              geometry := CreateWDGeometryFromSDOShape(query, 'SHAPE');
              projectGeometry(geometry, fSourceProjection);
              objects.Add(oid, TGeometryLayerObject.Create(Self, oid, geometry, value));
            end;
          5,9: // road/energy (VALUE_EXPR) and width (TEXTURE_EXPR) left and right, for energy right will be null -> NaN
            begin
              // Left and right
              value := FieldFloatValueOrNaN(query.Fields[1]);
              value2 := FieldFloatValueOrNaN(query.Fields[2]);
              texture := FieldFloatValueOrNaN(query.Fields[3]);
              texture2 := FieldFloatValueOrNaN(query.Fields[4]);
              geometry := CreateWDGeometryFromSDOShape(query, 'SHAPE');
              projectGeometry(geometry, fSourceProjection);
              objects.Add(oid, TUSRoadICLR.Create(Self, oid, geometry, value, value2, texture, texture2));
            end;
          21: // POI
            begin
              //
              geometryPoint := TWDGeometryPoint.Create;
              try
                geometryPoint.x := query.Fields[1].AsFloat;
                geometryPoint.y := query.Fields[2].AsFloat;
                // no projection, is already in lat/lon
                poiType := query.Fields[3].AsString;
                poiCat := query.Fields[4].AsString;
                if not fPoiCategories.TryGetValue(poicat+'_'+poiType, usPOI) then
                begin
                  usPOI := TUSPOI.Create(fNewPoiCatID, TPicture.Create);
                  fNewPoiCatID := fNewPoiCatID+1;
                  try
                    resourceFolder := ExtractFilePath(ParamStr(0));
                    usPOI.picture.Graphic.LoadFromFile(resourceFolder+poicat+'_'+poiType+'.png');
                  except
                    on e: Exception
                    do Log.WriteLn('Exception loading POI image '+resourceFolder+poicat+'_'+poiType+'.png', llError);
                  end;
                  // signal POI image to tiler
                  //ImageToBytes(usPOI);
                  //fTilerLayer.s
                  {
                  stream  := TBytesStream.Create;
                  try
                    usPOI.picture.Graphic.SaveToStream(stream);
                    fOutputEvent.signalEvent(TByteBuffer.bb_tag_tbytes(icehTilerPOIImage, stream.Bytes)); // todo: check correct number of bytes
                  finally
                    stream.Free;
                  end;
                  }
                end;
              finally
                objects.Add(oid, TGeometryLayerPOIObject.Create(Self, oid, usPOI.ID, geometryPoint));
              end;
            end
        else
          value := FieldFloatValueOrNaN(query.FieldByName('VALUE'));
          geometry := CreateWDGeometryFromSDOShape(query, 'SHAPE');
          projectGeometry(geometry, fSourceProjection);
          objects.Add(oid, TGeometryLayerObject.Create(Self, oid, geometry, value));
        end;
        *)
        query.Next;
      end;
    finally
      query.Free;
    end;
    Log.WriteLn(elementID+' ('+fLayerType.toString+'): '+name+', read objects (us)', llNormal, 1);
    // register with tiler
    RegisterLayer;
  finally
    oraSession.Free;
  end;
end;

procedure TUSLayer.RegisterLayer;
begin
  case fLayerType of
    1: // receptors
      RegisterOnTiler(False, SliceType, name, GetSetting(MaxEdgeLengthInMetersSwitchName, DefaultMaxEdgeLengthInMeters));
    //2:; grid
    3,  // buildings, polygon
    8,  // RS buildings, polygon
    4,  // road color (VALUE_EXPR) unidirectional, path, intensity
    5,  // road color (VALUE_EXPR) and width (TEXTURE_EXPR) left and right, path, intensity/capacity left/right
    9,  // energy color (VALUE_EXPR) and width (TEXTURE_EXPR), path, intensity/capacity unidirectional
    11, // points, basic layer
    21: // POI
      RegisterOnTiler(False, SliceType, name);
  end;
end;

procedure TUSLayer.RegisterSlice;
//var
  //poiImages: TArray<TPngImage>;
//  poi: TUSPOI;
//  palette: TWDPalette;
begin
  case fLayerType of
    1:   tilerLayer.signalAddSlice(fPalette.Clone); // receptors
    //2:; grid
    3,8: tilerLayer.signalAddSlice(fPalette.Clone); // buildings, RS buildings
    4:   tilerLayer.signalAddSlice(fPalette.Clone); // road color (VALUE_EXPR) unidirectional
    5:   tilerLayer.signalAddSlice(fPalette.Clone); // road color (VALUE_EXPR) and width (TEXTURE_EXPR) left and right
    9:   tilerLayer.signalAddSlice(fPalette.Clone); // energy color (VALUE_EXPR) and width (TEXTURE_EXPR)
    11:  tilerLayer.signalAddSlice(fPalette.Clone); // points, basic layer
    21: // POI
      begin
        // todo: does not work like this!!! TPicture <> TPngImage.. order of id..
        {
        for poi in fPoiCategories.Values do
        begin
          //
          if poi.ID>=length(poiImages)
          then setLength(poiImages, poi.ID+1);
          poiImages[poi.ID] := poi.picture;
        end;
        tilerLayer.signalAddPOISlice(poiImages);
        }
      end;
  end;
end;

function TUSLayer.SliceType: Integer;
begin
  // todo: implement
  case fLayerType of
    1:   Result := stReceptor; // receptors
    //2:; grid
    3,8: Result := stGeometry; // buildings, RS buildings
    4:   Result := stGeometryI; // road color (VALUE_EXPR) unidirectional
    5:   Result := stGeometryICLR; // road color (VALUE_EXPR) and width (TEXTURE_EXPR) left and right
    9:   Result := stGeometryIC; // energy color (VALUE_EXPR) and width (TEXTURE_EXPR)
    11:  Result := stLocation;  // points, basic layer
    21:  Result := stPOI; // POI
  else
         Result := stUndefined;
  end;
end;

{ TUSScenario }

constructor TUSScenario.Create(aProject: TProject; const aID, aName, aDescription: string; aAddBasicLayers: Boolean; aMapView: TMapView;
  aIMBConnection: TIMBConnection; const aTablePrefix: string);
begin
  fTablePrefix := aTablePrefix;
  fIMBConnection := aIMBConnection;
  inherited Create(aProject, aID, aName, aDescription, aAddbasicLayers, aMapView, false);
end;

procedure TUSScenario.ReadBasicData;

  procedure AddBasicLayer(const aID, aName, aDescription, aDefaultDomain, aObjectType, aGeometryType, aQuery: string;
    aLayerType: Integer; const aConnectString, aNewQuery, aChangeQuery: string; aOraSession: TOraSession; const aDataEvents: array of TIMBEventEntry; aSourceProjection: TGIS_CSProjectedCoordinateSystem);
  var
    layer: TUSLayer;
  begin
    layer := TUSLayer.Create(Self,
      standardIni.ReadString('domains', aObjectType, aDefaultDomain), //  domain
      aID, aName, aDescription, false,
       '"'+aObjectType+'"', aGeometryType , aLayerType, NaN,
       aConnectString,
       aNewQuery,
       aChangeQuery,
       aDataEvents,
       aSourceProjection,
       TDiscretePalette.Create('basic palette', [], TGeoColors.Create(colorBasicOutline)),
       True);
    layer.query := aQuery;
    Layers.Add(layer.ID, layer);
    Log.WriteLn(elementID+': added layer '+layer.ID+', '+layer.domain+'/'+layer.description, llNormal, 1);
    // schedule reading objects and send to tiler
    AddCommandToQueue(aOraSession, layer.ReadObjects);
  end;

  function SubscribeDataEvents(const aUserName, aIMBEventClass: string): TIMBEventEntryArray;
  var
    eventNames: TArray<System.string>;
    ev: string;
  begin
    setLength(Result, 0);
    eventNames := aIMBEventClass.Split([',']);
    for ev in eventNames do
    begin
      setLength(Result, Length(Result)+1);
      Result[Length(Result)-1] :=
        fIMBConnection.Subscribe(
          aUserName+
          fTableprefix.Substring(fTableprefix.Length-1)+ // #
          fTableprefix.Substring(0, fTablePrefix.length-1)+
          '.'+ev.Trim, False); // add with absolute path
    end;
  end;

var
  mlp: TPair<Integer, TMetaLayerEntry>;
  layer: TUSLayer;
  indicTableNames: TAllRowsSingleFieldResult;
  tableName: string;
  geneTables: TAllRowsSingleFieldResult;
  i: Integer;
  oraSession: TOraSession;
  metaLayer: TMetaLayer;
  connectString: string;
  sourceProjection: TGIS_CSProjectedCoordinateSystem;

  layerInfoKey: string;
  layerInfo: string;
  layerInfoParts: TArray<string>;

  dom: string;
  nam: string;
begin
  oraSession := (project as TUSProject).OraSession;
  with oraSession
  do connectString := userName+'/'+password+'@'+server;
  sourceProjection := (project as TUSProject).sourceProjection;

  // process basic layers
  if addBasicLayers then
  begin
    geneTables := ReturnAllFirstFields(oraSession,
      'SELECT DISTINCT OBJECT_NAME '+
      'FROM USER_OBJECTS '+
      'WHERE OBJECT_TYPE = ''TABLE'' AND OBJECT_NAME LIKE '''+fTablePrefix+'GENE%''');
    for i := 0 to Length(geneTables)-1 do
    begin
      tableName := geneTables[i];
      if tableName=fTablePrefix.ToUpper+'GENE_ROAD' then
      begin // always
        AddBasicLayer(
          'road', 'roads', 'roads', 'basic structures', 'road', 'LineString',
          'SELECT OBJECT_ID, 0 AS VALUE, t.SHAPE FROM '+tableName+' t',
          4, connectString, '', '', oraSession, SubscribeDataEvents(oraSession.Username, 'GENE_ROAD'), sourceProjection);
      end
      else if tableName=fTablePrefix.ToUpper+'GENE_PIPELINES' then
      begin // check count
        if ReturnRecordCount(oraSession, tableName)>0
        then AddBasicLayer(
               'pipeline', 'pipe lines', 'pipe lines', 'basic structures', 'pipe line', 'LineString',
               'SELECT OBJECT_ID, 0 AS VALUE, t.SHAPE FROM '+tableName+' t',
               4, connectString, '', '', oraSession, SubscribeDataEvents(oraSession.Username, 'GENE_PIPELINES'), sourceProjection);
      end
      else if tableName=fTablePrefix.ToUpper+'GENE_BUILDING' then
      begin // always
        AddBasicLayer(
          'building', 'buildings', 'buildings', 'basic structures', 'building', 'MultiPolygon',
          'SELECT OBJECT_ID, 0 AS VALUE, t.SHAPE FROM '+tableName+' t',
          3, connectString, '', '', oraSession, SubscribeDataEvents(oraSession.Username, 'GENE_BUILDING'), sourceProjection);
      end
      else if tableName=fTablePrefix.ToUpper+'GENE_SCREEN' then
      begin // always
        AddBasicLayer(
          'screen', 'screens', 'screens', 'basic structures', 'screen', 'LineString',
          'SELECT OBJECT_ID, 0 AS VALUE, t.SHAPE FROM '+tableName+' t',
          4, connectString, '', '', oraSession, SubscribeDataEvents(oraSession.Username, 'GENE_SCREEN'), sourceProjection);
      end
      else if tableName=fTablePrefix.ToUpper+'GENE_TRAM' then
      begin // check count
        if ReturnRecordCount(oraSession, tableName)>0
        then AddBasicLayer(
               'tramline', 'tram lines', 'tram lines', 'basic structures', 'tram line', 'LineString',
               'SELECT OBJECT_ID, 0 AS VALUE, t.SHAPE FROM '+tableName+' t',
               4, connectString, '', '', oraSession, SubscribeDataEvents(oraSession.Username, 'GENE_TRAM'), sourceProjection);
      end
      else if tableName=fTablePrefix.ToUpper+'GENE_BIKEPATH' then
      begin // check count
        if ReturnRecordCount(oraSession, tableName)>0
        then AddBasicLayer(
               'bikepath', 'bike paths', 'bike paths', 'basic structures', 'bike path', 'LineString',
               'SELECT OBJECT_ID, 0 AS VALUE, t.SHAPE FROM '+tableName+' t',
               4, connectString, '', '', oraSession, SubscribeDataEvents(oraSession.Username, 'GENE_BIKEPATH'), sourceProjection);
      end
      else if tableName=fTablePrefix.ToUpper+'GENE_RAIL' then
      begin // check count
        if ReturnRecordCount(oraSession, tableName)>0
        then AddBasicLayer(
               'railline', 'rail lines', 'rail lines', 'basic structures', 'rail line', 'LineString',
               'SELECT OBJECT_ID, 0 AS VALUE, t.SHAPE FROM '+tableName+' t',
               4, connectString, '', '', oraSession, SubscribeDataEvents(oraSession.Username, 'GENE_RAIL'), sourceProjection);
      end
      else if tableName=fTablePrefix.ToUpper+'GENE_INDUSTRY_SRC' then
      begin // check count
        if ReturnRecordCount(oraSession, tableName)>0
        then AddBasicLayer(
               'industrysource', 'industry sources', 'industry sources', 'basic structures', 'industry source', 'Point',
               'SELECT OBJECT_ID, 0 AS VALUE, t.SHAPE FROM '+tableName+' t',
               11, connectString, '', '', oraSession, SubscribeDataEvents(oraSession.Username, 'GENE_INDUSTRY_SRC'), sourceProjection);
      end;
      //GENE_NEIGHBORHOOD
      //GENE_RESIDENCE
      //GENE_NODE
      //GENE_DISTRICT
      //GENE_STUDY_AREA
      //GENE_BASCOV
    end;
  end;

  // process meta layer to build list of available layers
  metaLayer := TMetaLayer.Create;
  try
    ReadMetaLayer(oraSession, fTableprefix, metaLayer);
    Log.WriteLn(elementID+': found '+metaLayer.Count.ToString+' layers in meta_layer');
    for mlp in metaLayer do
    begin
      if mlp.Value._published>0 then
      begin

        // try tablename-value, legend description-value..
        layerInfoKey := mlp.Value.LAYER_TABLE.Trim+'-'+mlp.Value.VALUE_EXPR.trim;
        layerInfo := StandardIni.ReadString('layers', layerInfoKey, '');
        if layerInfo='' then
        begin
          layerInfoKey := mlp.Value.LEGEND_DESC.trim+'-'+mlp.Value.VALUE_EXPR.trim;
          layerInfo := StandardIni.ReadString('layers', layerInfoKey, '');
        end;

        if layerInfo<>'' then
        begin
          layerInfoParts := layerInfo.Split([',']);
          if length(layerInfoParts)<2 then
          begin
            setLength(layerInfoParts, 2);
            layerInfoParts[1] := mlp.Value.LEGEND_DESC;
          end;

          if mlp.Value.domain<>''
          then dom := mlp.Value.domain
          else dom := standardIni.ReadString('domains', layerInfoParts[0], layerInfoParts[0]);
          nam := layerInfoParts[1];

          layer := mlp.Value.CreateUSLayer(self, fTablePrefix, connectString, SubscribeDataEvents(oraSession.Username, mlp.Value.IMB_EVENTCLASS), sourceProjection, dom, name);
          if Assigned(layer) then
          begin
            Layers.Add(layer.ID, layer);
            Log.WriteLn(elementID+': added layer '+layer.ID+', '+layer.domain+'/'+layer.description, llNormal, 1);
            // schedule reading objects and send to tiler
            AddCommandToQueue(oraSession, layer.ReadObjects);
          end
          else Log.WriteLn(elementID+': skipped layer ('+mlp.Key.ToString+') type '+mlp.Value.LAYER_TYPE.ToString+' '+mlp.Value.LAYER_TABLE+'-'+mlp.Value.VALUE_EXPR, llRemark, 1);
        end;
      end;
    end;

    // process indicators
    indicTableNames := ReturnAllFirstFields(oraSession,
      'SELECT DISTINCT name FROM '+
      '( '+
      'SELECT table_name AS name '+
      'FROM user_tables '+       // aScenarioPrefix is case-sensitive
      'WHERE table_name LIKE '''+FTablePrefix+'%\_INDIC\_DEF%'' ESCAPE ''\'' '+
      ') '+
      'UNION '+
      '( '+
      'SELECT view_name AS name '+
      'FROM user_views '+
      'WHERE view_name LIKE '''+FTablePrefix+'%\_INDIC\_DEF%'' ESCAPE ''\'' '+
      ') '+
      'ORDER BY name');
    for tableName in indicTableNames do
    begin
      //fIndicators.Add(TIndicator.Create(Self, FModelControl.Connection, FDomainsEvent, FSession, FTablePrefix, FSessionName, tableName));
      Log.WriteLn(elementID+': added indicator: '+tableName, llNormal, 1);
    end;
    Log.WriteLn(elementID+': finished building scenario');
  finally
    metaLayer.Free;
  end;
end;

function TUSScenario.SelectObjects(aClient: TClient; const aType, aMode: string; const aSelectCategories, aSelectedIDs: TArray<string>): string;
begin
  // todo: implement
  Result := '';
end;

function TUSScenario.selectObjectsProperties(aClient: TClient; const aSelectCategories, aSelectedObjects: TArray<string>): string;
begin
  // todo: implement
  Result := '';
end;

function TUSScenario.SelectObjects(aClient: TClient; const aType, aMode: string; const aSelectCategories: TArray<string>; aGeometry: TWDGeometry): string;
var
  layers: TList<TLayer>;
  categories: string;
  objectsGeoJSON: string;
  totalObjectCount: Integer;
  extent: TWDExtent;
  l: TLayer;
  objectCount: Integer;
begin
  Result := '';
  layers := TList<TLayer>.Create;
  try
    if selectLayersOnCategories(aSelectCategories, layers) then
    begin
      categories := '';
      objectsGeoJSON := '';
      totalObjectCount := 0;
      extent := TWDExtent.FromGeometry(aGeometry);
      for l in layers do
      begin
        objectCount := l.findObjectsInGeometry(extent, aGeometry, objectsGeoJSON);
        if objectCount>0 then
        begin
          if categories=''
          then categories := '"'+l.id+'"'
          else categories := categories+',"'+l.id+'"';
          totalObjectCount := totalObjectCount+objectCount;
        end;
      end;
      Result :=
        '{"selectedObjects":{"selectCategories":['+categories+'],'+
         '"mode":"'+aMode+'",'+
         '"objects":['+objectsGeoJSON+']}}';
      Log.WriteLn('select on geometry:  found '+totalObjectCount.ToString+' objects in '+categories);
    end;
    // todo: else warning?
  finally
    layers.Free;
  end;
end;

function TUSScenario.SelectObjects(aClient: TClient; const aType, aMode: string; const aSelectCategories: TArray<string>; aX, aY, aRadius: Double): string;
var
  layers: TList<TLayer>;
  dist: TDistanceLatLon;
  nearestObject: TLayerObject;
  nearestObjectLayer: TLayer;
  nearestObjectDistanceInMeters: Double;
  l: TLayer;
  o: TLayerObject;
  categories: string;
  objectsGeoJSON: string;
  totalObjectCount: Integer;
  objectCount: Integer;
begin
  Result := '';
  layers := TList<TLayer>.Create;
  try
    if selectLayersOnCategories(aSelectCategories, layers) then
    begin
      dist := TDistanceLatLon.Create(aY, aY);
      if (aRadius=0) then
      begin
        nearestObject := nil;
        nearestObjectLayer := nil;
        nearestObjectDistanceInMeters := Infinity;
        for l in layers do
        begin
          o := l.findNearestObject(dist, aX, aY, nearestObjectDistanceInMeters);
          if assigned(o) then
          begin
            nearestObjectLayer := l;
            nearestObject := o;
            if nearestObjectDistanceInMeters=0
            then break;
          end;
        end;
        if Assigned(nearestObject) then
        begin
          // todo:
          Result :=
            '{"selectedObjects":{"selectCategories":["'+nearestObjectLayer.ID+'"],'+
             '"mode":"'+aMode+'",'+
             '"objects":['+nearestObject.JSON2D[nearestObjectLayer.geometryType, '']+']}}';
          Log.WriteLn('found nearest object layer: '+nearestObjectLayer.ID+', object: '+string(nearestObject.ID)+', distance: '+nearestObjectDistanceInMeters.toString);
        end;
      end
      else
      begin
        categories := '';
        objectsGeoJSON := '';
        totalObjectCount := 0;
        for l in layers do
        begin
          objectCount := l.findObjectsInCircle(dist, aX, aY, aRadius, objectsGeoJSON);
          if objectCount>0 then
          begin
            if categories=''
            then categories := '"'+l.id+'"'
            else categories := categories+',"'+l.id+'"';
            totalObjectCount := totalObjectCount+objectCount;
          end;
        end;
        Result :=
          '{"selectedObjects":{"selectCategories":['+categories+'],'+
           '"mode":"'+aMode+'",'+
           '"objects":['+objectsGeoJSON+']}}';
        Log.WriteLn('select on radius:  found '+totalObjectCount.ToString+' objects in '+categories);
      end;
    end;
    // todo: else warning?
  finally
    layers.Free;
  end;
end;

function TUSScenario.SelectObjects(aClient: TClient; const aType, aMode: string; const aSelectCategories: TArray<string>; aJSONQuery: TJSONArray): string;
var
  layers: TList<TLayer>;
begin
  Result := '';
  layers := TList<TLayer>.Create;
  try
    if selectLayersOnCategories(aSelectCategories, layers) then
    begin
      if aMode='+' then
      begin
        // only use first layer (only 1 type of object allowed..)
        // todo: warning if more then 1 layer?

      end
      else
      begin
        // select objects in layer that match first

      end;
    end;
    // todo: else warning?
  finally
    layers.Free;
  end;
end;

{ TUSDBScenario }

constructor TUSDBScenario.Create(const aID, aName, aDescription, aParentID, aReferenceID, aTablePrefix, aIMBPrefix, aStatus: string; aPublished: Integer);
begin
  inherited Create;
  fID := aID;
  fName := aName;
  fDescription := aDescription;
  fParentID := aParentID;
  fParentName := '';
  fReferenceID := aReferenceID;
  fReferenceName := '';
  fTablePrefix := aTablePrefix;
  fIMBPrefix := aIMBPrefix;
  fStatus := aStatus;
  fPublished := aPublished;
end;

procedure TUSDBScenario.Relink(aUSDBScenarios: TObjectDictionary<string, TUSDBScenario>);
var
  s: TUSDBScenario;
begin
  if aUSDBScenarios.TryGetValue(fParentID, s)
  then fParentName := s.name;
  if aUSDBScenarios.TryGetValue(fReferenceID, s)
  then fReferenceName := s.name;
end;

{ TUSProject }

constructor TUSProject.Create(aSessionModel: TSessionModel; aConnection: TConnection; aIMB3Connection: TIMBConnection;
  const aProjectID, aProjectName, aTilerFQDN, aTilerStatusURL: string;
  aDBConnection: TCustomConnection; aMapView: TMapView; aPreLoadScenarios: Boolean; aMaxNearestObjectDistanceInMeters: Integer);
var
  SourceEPSGstr: string;
  SourceEPSG: Integer;
begin
  fIMB3Connection := aIMB3Connection;
  fUSDBScenarios := TObjectDictionary<string, TUSDBScenario>.Create;
  mapView := aMapView;

  SourceEPSGstr := GetSetting(SourceEPSGSwitch, 'Amersfoort_RD_New');
  if SourceEPSGstr<>'' then
  begin
    SourceEPSG := StrToIntDef(SourceEPSGstr, -1);
    if SourceEPSG>0
    then fSourceProjection := CSProjectedCoordinateSystemList.ByEPSG(SourceEPSG)
    else fSourceProjection := CSProjectedCoordinateSystemList.ByWKT(SourceEPSGstr);
  end
  else fSourceProjection := CSProjectedCoordinateSystemList.ByWKT('Amersfoort_RD_New'); // EPSG: 28992
  fPreLoadScenarios := aPreLoadScenarios;
  inherited Create(aSessionModel, aConnection, aProjectID, aProjectName,
    aTilerFQDN, aTilerStatusURL,
    aDBConnection,
    0, False, False, False, False, addBasicLayers, '',
    aMaxNearestObjectDistanceInMeters);
end;

destructor TUSProject.Destroy;
begin
  FreeAndNil(fScenarioLinks);
  inherited;
  FreeAndNil(fUSDBScenarios);
end;

function TUSProject.getOraSession: TOraSession;
begin
  Result := fDBConnection as TOraSession;
end;

procedure TUSProject.ReadBasicData;
var
  scenarioID: Integer;
  s: string;
begin
  ReadScenarios;
  ReadMeasures;
  // load current scenario and ref scenario first
  scenarioID := getUSCurrentPublishedScenarioID(OraSession, GetCurrentScenarioID(OraSession));
  fProjectCurrentScenario := ReadScenario(scenarioID.ToString);
  Log.WriteLn('current US scenario: '+fProjectCurrentScenario.ID+' ('+(fProjectCurrentScenario as TUSScenario).fTableprefix+'): "'+fProjectCurrentScenario.description+'"', llOk);
  // ref
  scenarioID := GetScenarioBaseID(OraSession, scenarioID);
  if scenarioID>=0 then
  begin
    fProjectRefScenario := ReadScenario(scenarioID.ToString);
    Log.WriteLn('reference US scenario: '+fProjectRefScenario.ID+' ('+(fProjectRefScenario as TUSScenario).fTableprefix+'): "'+fProjectRefScenario.description+'"', llOk);
  end
  else Log.WriteLn('NO reference US scenario', llWarning);
  if fPreLoadScenarios then
  begin
    for s in fUSDBScenarios.Keys do
    begin
      if fUSDBScenarios[s]._published>0
      then ReadScenario(s);
    end;
  end;
end;

procedure TUSProject.ReadMeasures;
var
  measures: TAllRowsResults;
  m: Integer;
begin
  // todo:
  measures := ReturnAllResults(OraSession,
    'SELECT OBJECT_ID, Category, Measure, Description, ObjectTypes, Action, Action_Parameters, Action_ID '+
    'FROM META_MEASURES');
  for m := 0 to length(measures)-1 do
  begin
    //

  end;
  // todo:
  Self.measuresEnabled := length(measures)>0;
  Self.measuresHistoryEnabled := Self.measuresEnabled;
end;

function TUSProject.ReadScenario(const aID: string): TScenario;
var
  dbScenario: TUSDBScenario;
begin
  System.TMonitor.Enter(fScenarios);
  try
    if not fScenarios.TryGetValue(aID, Result) then
    begin
      if fUSDBScenarios.TryGetValue(aID, dbScenario) then
      begin
        //StatusInc;
        Result := TUSScenario.Create(Self, aID, dbScenario.name, dbScenario.description, addBasicLayers, mapView, fIMB3Connection, dbScenario.tablePrefix);
        fScenarios.Add(Result.ID, Result);
      end
      else Result := nil;
    end;
  finally
    System.TMonitor.Exit(fScenarios);
  end;
end;

procedure TUSProject.ReadScenarios;
var
  scenarios: TAllRowsResults;
  s: Integer;
  usdbScenario: TUSDBScenario;
  isp: TPair<string, TUSDBScenario>;
begin
  // read scenarios from project database
  try
    scenarios := ReturnAllResults(OraSession,
      'SELECT ID, Name, Federate, Parent_ID, Base_ID, Notes, SCENARIO_STATUS, PUBLISHED '+
      'FROM META_SCENARIOS '+
      'ORDER BY ID ASC');
    for s := 0 to Length(scenarios)-1 do
    begin
      usdbScenario := TUSDBScenario.Create(scenarios[s][0], scenarios[s][1], scenarios[s][5],
        scenarios[s][3], scenarios[s][4], scenarios[s][1]+'#', scenarios[s][2], scenarios[s][6], StrToIntDef(scenarios[s][7], 0));
      fUSDBScenarios.Add(usdbScenario.id, usdbScenario);
      if scenarios[s][7]='1' then
      begin
        fScenarioLinks.children.Add(TScenarioLink.Create(
          usdbScenario.ID, usdbScenario.parentID, usdbScenario.referenceID,
          usdbScenario.name, usdbScenario.description, scenarios[s][6], nil));
      end;
    end;
  except
    Log.WriteLn('Could not read scenarios, could be published field -> try without', llWarning);
    scenarios := ReturnAllResults(OraSession,
      'SELECT ID, Name, Federate, Parent_ID, Base_ID, Notes, SCENARIO_STATUS '+
      'FROM META_SCENARIOS '+
      //'WHERE SCENARIO_STATUS=''OPEN'''+
      'ORDER BY ID ASC');
    for s := 0 to Length(scenarios)-1 do
    begin
      usdbScenario := TUSDBScenario.Create(scenarios[s][0], scenarios[s][1], scenarios[s][5],
        scenarios[s][3], scenarios[s][4], scenarios[s][1]+'#', scenarios[s][2], scenarios[s][6], 1);
      fUSDBScenarios.Add(usdbScenario.id, usdbScenario);
      fScenarioLinks.children.Add(TScenarioLink.Create(
        usdbScenario.ID, usdbScenario.parentID, usdbScenario.referenceID,
        usdbScenario.name, usdbScenario.description, scenarios[s][6], nil));
    end;
  end;
  // (re)link
  for isp in fUSDBScenarios
  do isp.Value.Relink(fUSDBScenarios);
  // build hierarchy
  if GetSetting(UseScenarioHierarchySwitch, False)
  then fScenarioLinks.buildHierarchy() // todo: use hierarchy via setting?
  else fScenarioLinks.sortChildren(); // todo: sort scenario links?
  // filter closed 'leaves'
  fScenarioLinks.removeLeaf('CLOSED');
end;

function getUSMapView(aOraSession: TOraSession; const aDefault: TMapView): TMapView;
var
  table: TOraTable;
begin
  // try to read view from database
  table := TOraTable.Create(nil);
  try
    table.Session := aOraSession;
    table.SQL.Text :=
      'SELECT Lat, Lon, Zoom '+
      'FROM PUBL_PROJECT';
    table.Execute;
    try
      if table.FindFirst
      then Result := TMapView.Create(table.Fields[0].AsFloat, table.Fields[1].AsFloat, table.Fields[2].AsInteger)
      else Result := aDefault;
    finally
      table.Close;
    end;
  finally
    table.Free;
  end;
end;

function getUSProjectID(aOraSession: TOraSession; const aDefault: string): string;
var
  table: TOraTable;
begin
  // try to read project info from database
  table := TOraTable.Create(nil);
  try
    table.Session := aOraSession;
    table.SQL.Text :=
      'SELECT ProjectID '+
      'FROM PUBL_PROJECT';
    table.Execute;
    try
      if table.FindFirst then
      begin
        if not table.Fields[0].IsNull
        then Result := table.Fields[0].AsString
        else Result := aDefault;
      end
      else Result := aDefault;
    finally
      table.Close;
    end;
  finally
    table.Free;
  end;
end;

procedure setUSProjectID(aOraSession: TOraSession; const aValue: string);
begin
  aOraSession.ExecSQL(
    'UPDATE PUBL_PROJECT '+
    'SET ProjectID='''+aValue+'''');
  aOraSession.Commit;
end;

function getUSCurrentPublishedScenarioID(aOraSession: TOraSession; aDefault: Integer): Integer;
var
  table: TOraTable;
begin
  // try to read project info from database
  table := TOraTable.Create(nil);
  try
    table.Session := aOraSession;
    table.SQL.Text :=
      'SELECT StartPublishedScenarioID '+
      'FROM PUBL_PROJECT';
    table.Execute;
    try
      if table.FindFirst then
      begin
        if not table.Fields[0].IsNull
        then Result := table.Fields[0].AsInteger
        else Result := aDefault;
      end
      else Result := aDefault;
    finally
      table.Close;
    end;
  finally
    table.Free;
  end;
end;

end.
