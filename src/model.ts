export type Camera={center:[number,number];zoom:number;bearing:number;pitch:number};
export type Pane={type:'modern'|'history'|'image';contentId?:string;transform?:{scale:number;x:number;y:number}};
export type LiveState={panes:[Pane,Pane?];split:boolean;camera:Camera;mode:'live'|'free';revision:number};
export type Content={id:string;title:string;storage_path:string;url?:string};
export type Marker={id:string;session_id:string;lat:number;lng:number;title:string;description:string;photo_path:string|null;photo_url?:string;resource_url:string|null};
export type Task={id:string;marker_id:string;session_id:string;question:string;kind:'read'|'complete'|'short';access:'anytime'|'arrival';radius_m:number};
export type Annotation={id:string;layer:'image'|'map';content_id:string|null;kind:'free'|'circle'|'line'|'arrow'|'box';points:[number,number][]};
export const INITIAL:LiveState={panes:[{type:'modern'}],split:false,camera:{center:[139.7966,35.7148],zoom:14,bearing:0,pitch:0},mode:'live',revision:0};
export function distance(a:[number,number],b:[number,number]) {const r=Math.PI/180, dlat=(b[1]-a[1])*r,dlng=(b[0]-a[0])*r,x=Math.sin(dlat/2)**2+Math.cos(a[1]*r)*Math.cos(b[1]*r)*Math.sin(dlng/2)**2;return 12742000*Math.atan2(Math.sqrt(x),Math.sqrt(1-x));}
export const HISTORY_STYLE='https://mierune.github.io/rekichizu-style/styles/street/style.json';
export const MODERN_STYLE={version:8 as const,sources:{gsi:{type:'raster' as const,tiles:['https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png'],tileSize:256,attribution:'<a href="https://maps.gsi.go.jp/development/ichiran.html" target="_blank" rel="noopener noreferrer">国土地理院・地理院タイル</a>'}},layers:[{id:'gsi',type:'raster' as const,source:'gsi'}]};
