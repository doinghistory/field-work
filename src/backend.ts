import {createClient, type SupabaseClient} from '@supabase/supabase-js';
import type {LiveState, Content, Marker, Task, Annotation} from './model';
const url=import.meta.env.VITE_SUPABASE_URL,key=import.meta.env.VITE_SUPABASE_ANON_KEY;
export const configured=!!(url&&key);
export const db:SupabaseClient|null=configured?createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true}}):null;
export type Data={state:LiveState;contents:Content[];markers:Marker[];tasks:Task[];annotations:Annotation[];location:[number,number]|null;completions:{task_id:string;user_id:string}[]};
export async function loadData(sid:string):Promise<Data>{
 if(!db) throw Error('Supabaseの設定が必要です');
 const tables=['session_state','content_items','markers','tasks','annotations','teacher_location','task_completions'] as const;
 const results=await Promise.all(tables.map(t=>db!.from(t).select('*').eq('session_id',sid)));
 for(const result of results) if(result.error) throw result.error;
 const [state,contents,markers,tasks,annotations,location,completions]=results.map(r=>r.data||[]);
 const signed=await Promise.all((contents as Content[]).map(async c=>({...c,url:(await db!.storage.from('fieldwork-images').createSignedUrl(c.storage_path,3600)).data?.signedUrl})));
 const signedMarkers=await Promise.all((markers as Marker[]).map(async m=>({...m,photo_url:m.photo_path?(await db!.storage.from('fieldwork-images').createSignedUrl(m.photo_path,3600)).data?.signedUrl:undefined})));
 return {state:{...((state[0] as {state:LiveState}|undefined)?.state||{})} as LiveState,contents:signed,markers:signedMarkers,tasks:tasks as Task[],annotations:annotations as Annotation[],location:location[0]?[location[0].lng,location[0].lat]:null,completions:completions as Data['completions']};
}
export async function requireUser(){if(!db) throw Error('Supabase未設定');const {data}=await db.auth.getUser();if(data.user) return data.user; const result=await db.auth.signInAnonymously();if(result.error) throw result.error;return result.data.user!;}
export async function errorOrThrow<T extends {error:unknown}>(promise:PromiseLike<T>){const result=await promise;if(result.error) throw result.error;return result;}
