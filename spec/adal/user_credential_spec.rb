#-------------------------------------------------------------------------------
# # Copyright (c) Microsoft Open Technologies, Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#   http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A
# PARTICULAR PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
#
# See the Apache License, Version 2.0 for the specific language
# governing permissions and limitations under the License.
#-------------------------------------------------------------------------------

require_relative '../spec_helper'

include FakeData

describe ADAL::UserCredential do
  let(:user_cred) { ADAL::UserCredential.new(USERNAME, PASSWORD) }
  let(:fed_url) { 'https://abc.def/' }

  before(:each) do
    expect(Net::HTTP).to receive(:get).once.and_return(
      "{\"account_type\": \"#{account_type}\", " \
      "\"federation_metadata_url\": \"#{fed_url}\"}")
  end

  context 'with a federated user' do
    let(:account_type) { 'Federated' }

    describe '#account_type' do
      subject { user_cred.account_type }

      it { is_expected.to eq ADAL::UserCredential::AccountType::FEDERATED }

      it 'should cache the response instead of making multiple HTTP requests' do
        # Note the .once in the before block.
        user_cred.account_type
        user_cred.account_type
      end
    end

    describe '#request_params' do
      subject { user_cred.request_params }
      let(:action) do
        'http://docs.oasis-open.org/ws-sx/ws-trust/200512/RSTRC/IssueFinal'
      end
      let(:grant_type) { 'grant_type' }
      let(:token) { 'token' }
      let(:wstrust_url) { 'https://ghi.jkl/' }

      before(:each) do
        expect_any_instance_of(ADAL::MexRequest).to receive(:execute)
          .and_return(double(wstrust_url: wstrust_url, action: action))
        expect_any_instance_of(ADAL::WSTrustRequest).to receive(:execute)
          .and_return(double(token: token, grant_type: grant_type))
      end

      it 'contains assertion, grant_type and scope' do
        expect(subject.keys).to contain_exactly(:assertion, :grant_type, :scope)
      end

      describe 'assertion' do
        subject { user_cred.request_params[:assertion] }

        it 'contains the base64 encoded token' do
          expect(Base64.decode64(subject)).to eq token
        end
      end

      describe 'scope' do
        subject { user_cred.request_params[:scope] }

        it { is_expected.to eq :openid }
      end
    end
  end

  context 'with a managed user' do
    let(:account_type) { 'Managed' }

    describe '#account_type' do
      subject { user_cred.account_type }
      it { is_expected.to eq ADAL::UserCredential::AccountType::MANAGED }
    end

    describe '#request_params' do
      it 'should contain username, password and grant type' do
        expect(user_cred.request_params.keys).to contain_exactly(
          :username, :password, :grant_type, :scope)
      end

      describe 'grant_type' do
        subject { user_cred.request_params[:grant_type] }

        it { is_expected.to eq 'password' }
      end
    end
  end

  context 'with an unknown account type user' do
    let(:account_type) { 'Unknown' }

    describe '#account_type' do
      subject { user_cred.account_type }
      it { is_expected.to eq ADAL::UserCredential::AccountType::UNKNOWN }
    end

    describe '#request_params' do
      it 'should throw an error' do
        expect { user_cred.request_params }.to raise_error(
          ADAL::UserCredential::UnsupportedAccountTypeError)
      end
    end
  end
end
