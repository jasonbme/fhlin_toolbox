function [R,G,C]=pmri_grappa_core(varargin)
%
%	pmri_grappa_core		perform GRAPPA reconstruction
%
%
%	[R]=pmri_grappa_core('obs',obs,'sample_vector',sample_vector,'acc_vector',acc_vector,'G',G,'flag_display', 1);
%
%	INPUT:
%	obs: input accelerated data of [n_PE, n_FE, n_chan]. 
%		n_PE: # of phase encoding
%		n_FE: # of frequency encoding
%		n_chan: # of channel
%	sample_vector: 1D vector with entries of 0 or 1: [1, n_PE].
%		n_PE: # of phase encoding steps before acceleration
%		"0" indicates the correponding entries are not sampled in accelerated scan.
%		"1" indicates the correponding entries are sampled in accelerated scan.
%	acc_vector: 1D vector: [1, n_PE].
%		n_PE: # of phase encoding steps before acceleration
%		"0" indicates the correponding entries are sampled in accelerated scan.
%		Other numerical values indicates the correponding entries are NOT sampled in accelerated scan. 
%		But they belong to the same reconstruction kernel
%	G: GRAPPA reconstruction kernel
%		It contains the reconstruction coefficients and definitions of acceleration scans and auto-calibration scans.
%	'flag_display': value of either 0 or 1
%		It indicates of debugging information is on or off.
%	'flag_common_coil': value of either 0 or 1 (default: 1)
%		It indicates use same GRAPPA kernel for all coils (default) or separate GRAPPA kernels for individual coil.
%
%	example:the following indicates a R=3 acceleration for 24 PE lines with line 11, 12, 14, 15 as auto-calibration scan (ACS) lines
%		sample_vector = [1 0 0 1 0 0 1 0 0 1 1 1 1 1 1 1 0 0 1 0 0 1 0 0];
%		acc_vector    = [0 1 2 0 1 2 0 1 2 0 1 2 0 1 2 0 1 2 0 1 2 0 1 2];
%
%	OUTPUT:
%	R: GRAPPA reconstruction of [n_PE, n_FE, n_chan]. 
%		n_PE: # of phase encoding
%		n_FE: # of frequency encoding
%		n_chan: # of channel
%
%---------------------------------------------------------------------------------------
%	Fa-Hsuan Lin, Athinoula A. Martinos Center, Mass General Hospital
%
%	fhlin@nmr.mgh.harvard.edu
%
%	fhlin@mar. 20, 2005
%   fhlin@nov. 10, 2005

R=[];
P=[];

obs=[];

sample_vector=[];
acc_vector=[];
acs_vector=[];

flag_display=0;
flag_reg=0;
flag_common_coil=1;
flag_smooth_constraint=0;

for i=1:floor(length(varargin)/2)
    option=varargin{i*2-1};
    option_value=varargin{i*2};
    switch lower(option)
        case 'r'
            R=option_value;
        case 'p'
            P=option_value;
        case 'g'
            G=option_value;
        case 'obs'
            obs=option_value;
        case 'sample_vector';
            sample_vector=option_value;
        case 'acc_vector';
            acc_vector=option_value;
        case 'acs_vector';
            acs_vector=option_value;
        case 'flag_common_coil'
            flag_common_coil=option_value;
        case 'flag_reg'
            flag_reg=option_value;
        case 'flag_smooth_constraint'
            flag_smooth_constraint=option_value;
        case 'flag_display'
            flag_display=option_value;
        otherwise
            fprintf('unknown option [%s]!\n',option);
            fprintf('error!\n');
            return;
    end;
end;


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%	check data
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if(flag_display)
    fprintf('\tchecking data and ACC info...\n');
end;
xx=length(find(sample_vector(:)|acc_vector(:)));


if(xx~=size(obs,1))
    fprintf('\tACC and sampling information error [GAP in k-space]!\n\n');
    return;
end;

xx=find(acc_vector==0);
if(length(find(sample_vector(xx)==0))>0)
    fprintf('\tACC and sampling information error! [Sampling leakage]\n\n');
    return;
end;

if(flag_display)
    fprintf('\tgrappa reconstruction...\n');
end;

%finding ACC tokens
sacc=sort(acc_vector);
acc_token_idx=find(diff(sacc))+1;
acc_token_idx=[1 acc_token_idx];
acc_token=sacc(acc_token_idx);
acc_token=setdiff(acc_token,0);     % token [0] is reserved as the actual sampled data
if(flag_display)
    fprintf('\tfinding [%d] ACC tokens : {%s}\n',length(acc_token),mat2str(acc_token));
end;

if(flag_smooth_constraint)
    fprintf('smooth constraint, preparing laplacian...\n');
    S=2.*eye(length(acc_vector))+circshift(eye(length(acc_vector)).*-1,[0 1])+circshift(eye(length(acc_vector)).*-1,[0 -1]);
    S(1,:)=0; S(1,1)=2; S(1,2)=-2;
    S(end,:)=0; S(end,end)=2; 
    Rsmooth=inv(S*S');
else
    Rsmooth=eye(length(acc_vector));
end;


if(isempty(R))
    %	R=ones(size(A,2),size(Y,2));
    R=ones(size(Rsmooth));
end;
R=R*Rsmooth;
r_p=sqrt(R);
r_n=sqrt(pinv(r_p));

R=obs;
for i=1:length(acc_token)
    
    phase_encode_grappa_block=G{i}.phase_encode_grappa_block;
    freq_encode_grappa_block=G{i}.freq_encode_grappa_block;
    
    if(flag_display)
        fprintf('\ttoken [%d] kernel...',acc_token(i));
    end;
    %     if(isempty(acs_vector))
    %     	acs_vector=intersect(find(acc_vector==acc_token(i)),find(sample_vector));
    %         acs_idx=acs_vector;
    %     end;
    %     acs_idx=acs_vector;
    %     
    %     if(isempty(acs_idx))
    %         fprintf('cannot find ACS lines!'); return;
    %     end;
    acs_idx=find(acc_vector==acc_token(i));
    
    %acs_idx=intersect(find(acc_vector==acc_token(i)),find(sample_vector==0));
    %acs_idx=find(acc_vector==acc_token(i));
    if(flag_display)
        fprintf('DATA lines : %s...\n',mat2str(acs_idx));
    end;
    
    %prepare frequency encoding block indices (cyclic indices)
    freq_idx=[];
    for j=-freq_encode_grappa_block:freq_encode_grappa_block
        freq_idx=cat(1,freq_idx,[j:j+size(obs,2)-1]);
    end;
    freq_idx=freq_idx+1;
    freq_idx=mod(freq_idx,size(obs,2));
    freq_idx(find(freq_idx==0))=size(obs,2);
    
    reg=[];
    
    for ff=1:size(freq_idx,2)
        A=[];
	if(flag_display) fprintf('\tgrappa recon freqency encoding [%d|%d]',ff,size(freq_idx,2)); end;
        for j=1:length(acs_idx)
            
            acc_idx=find(acc_vector==0);
            acc_idx=sort(union(acc_idx,acs_idx(j)));
            %acc_idx=sort(union(acc_idx,acs_idx));
            acc_block_idx=[1:length(acc_idx)];
            acc_block_idx=acc_block_idx-find(acc_idx==acs_idx(j));
            %acc_block_idx=acc_block_idx-find(acc_idx==acs_idx);
            acc_block_idx=setdiff(acc_block_idx,0);
            acc_idx=setdiff(acc_idx,acs_idx(j));
            %acc_idx=setdiff(acc_idx,acs_idx);
            idx=find(abs(acc_block_idx)<=phase_encode_grappa_block);
            bidx=acc_block_idx(idx);
            
            T=zeros(length(G{i}.block_idx),size(freq_idx,1),size(obs,3));
            
            tmp=obs(acc_idx(idx),freq_idx(:,ff),:);
            [dummy,xx]=intersect(G{i}.block_idx,bidx);
            
            T(xx,:,:)=tmp;
            tmp=permute(T,[2,1,3]);
            
            A0=transpose(tmp(:));
            
            if(flag_common_coil)
                A0=repmat(A0,[size(obs,3),1]);
            end;
            
            A=cat(1,A,A0);
        end;

        if(flag_reg)% regularized
            [v_e,sinv_e,u_e]=svd(A);
            s_e=pinv(sinv_e)';
            %[u_e,s_e,v_e]=svd(pinv(A));
            if(size(s_e,2)<size(s_e,1))
                s_e(:,end+1:size(s_e,1))=0;
            end;
            
            %this regularization is for ismrm2006 abstract
            %qq(acs_idx(j))=abs(size(P,1)/2+1-acs_idx(j))./size(P,1).*5;
            qq(acs_idx(j))=abs(size(P,1)/2+0.5-acs_idx(j))./size(P,1).*5;
            lambda=s_e(1,1)./qq(acs_idx(j));
            
            %new lambda on 040606
            %lambda=max(diag(s_e)).*0.1;
            lambda=max(diag(s_e)).*0.05;  %071906
		

            if(flag_common_coil)
                
                Gamma=zeros(size(s_e));
                
                %Gamma=diag(diag(s_e)./(diag(s_e).^2+lambda.^2))';
                Gamma=s_e./(s_e.^2+lambda.^2);
                
                Phi=diag(lambda.^2./(diag(s_e).^2+lambda.^2));
                %Phi=lambda.^2./(s_e.^2+lambda.^2);
                
                pp=P(acs_idx(j),:,:);

                tmp=v_e*Gamma*u_e'*G{i}.beta+v_e*(Phi*v_e'*pp(:));
                %tmp=v_e*(v_e'*pp(:));
                recon=permute(reshape(tmp,[size(freq_idx,2),size(obs,3),length(acs_idx(j))]),[3,1,2]);
            else
                tmp=[];
                for coil_idx=1:size(obs,3)
		    if(flag_display) fprintf('.'); end;
                    %pp=P(acs_idx(j),ff,coil_idx);
                    pp=P(acs_idx,ff,coil_idx);
                    
%                     ss=diag(s_e);
%                     ss(end+1:max(size(s_e)))=0;
%                     [lambda,rho,eta,reg_param,rho_c,eta_c] = inverse_lcurve(u_e,ss,G{i}.beta{coil_idx});
                    
                    Gamma=zeros(size(s_e));
                    
		    %Gamma=diag(diag(s_e)./(diag(s_e).^2+lambda.^2))';
                    Gamma=s_e./(s_e.^2+lambda.^2);
                    
                    Phi=diag(lambda.^2./(diag(s_e).^2+lambda.^2));
                    %Phi=lambda.^2./(s_e.^2+lambda.^2);
                    
                    tmpp=v_e*Gamma*u_e'*G{i}.beta{coil_idx}+v_e*(Phi*v_e'*pp(:));
                    %tmp=cat(3,tmp,reshape(tmpp,[1,length(acs_idx(j))]));
                    tmp=cat(3,tmp,reshape(tmpp,[1,length(acs_idx)]));
                end;
                recon=permute(tmp,[2,1,3]);               
            end;
        else %unregularized
            if(flag_common_coil)
                keyboard;
                recon=permute(reshape(A*G{i}.beta,[size(freq_idx,2),size(obs,3),length(acs_idx(j))]),[3,1,2]);
            else
                tmp=[];
                for coil_idx=1:size(obs,3)
                    %tmp=cat(3,tmp,reshape(A*G{i}.beta{coil_idx},[1,length(acs_idx(j))]));
                    tmp=cat(3,tmp,reshape(A*G{i}.beta{coil_idx},[1,length(acs_idx)]));
                end;
                recon=permute(tmp,[2,1,3]);    
            end;
        end;
        
        
        %R(acs_idx(j),ff,:)=recon;
        R(acs_idx,ff,:)=recon;
        
        %end;
        %the rows of A is nested: # of frequency_encoding -> # of coil -> # of phase_encoding
        
	if(flag_display) fprintf('\r'); end;
    end;
    
    if(flag_display)
        fprintf('\n');
    end;
end;

if(flag_display)
    fprintf('grappa core done!\n');
end;

return;

